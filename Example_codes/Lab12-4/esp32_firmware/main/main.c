#include <stdio.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <strings.h>
#include "esp_wifi.h"
#include "esp_system.h"
#include "nvs_flash.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "driver/gpio.h"
#include "esp_adc/adc_oneshot.h"
#include "mqtt_client.h"
#include "cJSON.h"

/* ========================================================
 * 0. การกำหนดค่าเครือข่าย Wi-Fi, Broker และ GPIO
 * ======================================================== */
#define WIFI_SSID           "AIS 4G Hi-Speed Home WiFi_769475"
#define WIFI_PASS           "50769475"

// หมายเลข IP ของคอมพิวเตอร์ที่รัน Mosquitto Broker (พอร์ต 1883)
#define MQTT_BROKER_URI     "mqtt://192.168.0.107:1883"

// กำหนดขาฮาร์ดแวร์สำหรับบอร์ด ESP32 มาตรฐาน (NodeMCU / DevKit)
#define LED_PIN             GPIO_NUM_2      // หลอดไฟ LED ต่อขา GPIO 2 (หรือ Onboard Blue LED)
#define ADC_CHANNEL         ADC_CHANNEL_6   // Potentiometer ต่อขา GPIO 34 (ADC1_CH6)

// หัวข้อ MQTT ตามมาตรฐาน Week 12
#define TOPIC_STATUS        "iot/esp32/status"
#define TOPIC_CONTROL       "iot/esp32/control"
#define TOPIC_LED_ACK       "iot/esp32/led_ack"
#define TOPIC_TELEMETRY     "iot/esp32/telemetry"

static const char *TAG = "LAB12_4_ESP32";
static EventGroupHandle_t s_wifi_event_group;
#define WIFI_CONNECTED_BIT  BIT0

static esp_mqtt_client_handle_t s_mqtt_client = NULL;
static adc_oneshot_unit_handle_t s_adc_handle = NULL;
static bool s_led_state = false;

/* ========================================================
 * 1. ระบบเชื่อมต่อ Wi-Fi Station
 * ======================================================== */
static void wifi_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        ESP_LOGW(TAG, "Wi-Fi disconnected, reconnecting...");
        esp_wifi_connect();
        xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "Got IP Address: " IPSTR, IP2STR(&event->ip_info.ip));
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

static void wifi_init_sta(void)
{
    s_wifi_event_group = xEventGroupCreate();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    esp_event_handler_instance_t instance_any_id;
    esp_event_handler_instance_t instance_got_ip;
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL, &instance_any_id));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &wifi_event_handler, NULL, &instance_got_ip));

    wifi_config_t wifi_config = {
        .sta = {
            .threshold.authmode = WIFI_AUTH_WPA2_PSK,
        },
    };
    size_t ssid_len = strlen(WIFI_SSID);
    if (ssid_len > sizeof(wifi_config.sta.ssid)) ssid_len = sizeof(wifi_config.sta.ssid);
    memcpy(wifi_config.sta.ssid, WIFI_SSID, ssid_len);

    size_t pass_len = strlen(WIFI_PASS);
    if (pass_len > sizeof(wifi_config.sta.password)) pass_len = sizeof(wifi_config.sta.password);
    memcpy(wifi_config.sta.password, WIFI_PASS, pass_len);

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    ESP_ERROR_CHECK(esp_wifi_start());
    ESP_LOGI(TAG, "Wi-Fi Initialization finished.");
}

/* ========================================================
 * 2. การจัดการ MQTT Event Handler
 * ======================================================== */
static void mqtt_event_handler(void *handler_args, esp_event_base_t base, int32_t event_id, void *event_data)
{
    esp_mqtt_event_handle_t event = (esp_mqtt_event_handle_t)event_data;
    esp_mqtt_client_handle_t client = event->client;

    switch ((esp_mqtt_event_id_t)event_id) {
    case MQTT_EVENT_CONNECTED:
        ESP_LOGI(TAG, "MQTT_EVENT_CONNECTED: Connected to Broker!");
        
        // ส่งข้อความสถานะ Online ทันทีที่เชื่อมต่อ (Retain = 1, QoS = 1)
        esp_mqtt_client_publish(client, TOPIC_STATUS, "online", 0, 1, 1);
        ESP_LOGI(TAG, "Published LWT online status to: %s", TOPIC_STATUS);

        // บอกรับหัวข้อคำสั่งควบคุม LED จาก Flutter App
        esp_mqtt_client_subscribe(client, TOPIC_CONTROL, 1);
        ESP_LOGI(TAG, "Subscribed to: %s", TOPIC_CONTROL);
        break;

    case MQTT_EVENT_DISCONNECTED:
        ESP_LOGW(TAG, "MQTT_EVENT_DISCONNECTED");
        break;

    case MQTT_EVENT_DATA:
        ESP_LOGI(TAG, "MQTT_EVENT_DATA received on topic: %.*s", event->topic_len, event->topic);
        ESP_LOGI(TAG, "Payload: %.*s", event->data_len, event->data);

        // ตรวจสอบหัวข้อควบคุม ("iot/esp32/control")
        if (strncmp(event->topic, TOPIC_CONTROL, event->topic_len) == 0) {
            char buf[128] = {0};
            int len = event->data_len < sizeof(buf) - 1 ? event->data_len : sizeof(buf) - 1;
            memcpy(buf, event->data, len);

            bool new_state = s_led_state;
            bool valid_cmd = false;

            // พยายามถอดรหัส JSON: {"led": "ON"} หรือ {"led": "OFF"}
            cJSON *json = cJSON_Parse(buf);
            if (json != NULL) {
                cJSON *led_item = cJSON_GetObjectItem(json, "led");
                if (led_item != NULL) {
                    if (cJSON_IsString(led_item)) {
                        if (strcasecmp(led_item->valuestring, "ON") == 0) {
                            new_state = true;
                            valid_cmd = true;
                        } else if (strcasecmp(led_item->valuestring, "OFF") == 0) {
                            new_state = false;
                            valid_cmd = true;
                        }
                    } else if (cJSON_IsBool(led_item)) {
                        new_state = cJSON_IsTrue(led_item);
                        valid_cmd = true;
                    }
                }
                cJSON_Delete(json);
            } else {
                // Fallback: รองรับ Plaintext "ON" หรือ "OFF"
                if (strcasecmp(buf, "ON") == 0) {
                    new_state = true;
                    valid_cmd = true;
                } else if (strcasecmp(buf, "OFF") == 0) {
                    new_state = false;
                    valid_cmd = true;
                }
            }

            if (valid_cmd) {
                s_led_state = new_state;
                gpio_set_level(LED_PIN, s_led_state ? 1 : 0);
                ESP_LOGI(TAG, "LED State updated -> %s (GPIO %d)", s_led_state ? "HIGH (ON)" : "LOW (OFF)", LED_PIN);

                // ส่งการตอบรับสถานะกลับไปยังแอป Flutter (Acknowledge State)
                // รูปแบบ: {"led_state": true, "ack": true}
                char ack_msg[64];
                snprintf(ack_msg, sizeof(ack_msg), "{\"led_state\": %s, \"ack\": true}", s_led_state ? "true" : "false");
                esp_mqtt_client_publish(client, TOPIC_LED_ACK, ack_msg, 0, 1, 0);
                ESP_LOGI(TAG, "Published ACK: %s to %s", ack_msg, TOPIC_LED_ACK);
            }
        }
        break;

    default:
        break;
    }
}

/* ========================================================
 * 3. FreeRTOS Task: ส่ง Telemetry เป็นระยะ (ทุก 500 ms)
 * ======================================================== */
static void telemetry_task(void *pvParameters)
{
    while (1) {
        vTaskDelay(pdMS_TO_TICKS(500)); // สตรีมข้อมูลทุก 500 ms เพื่อให้ Gauge และ Sparkline นุ่มนวล

        if (s_mqtt_client != NULL) {
            int adc_raw = 0;
            if (s_adc_handle != NULL) {
                adc_oneshot_read(s_adc_handle, ADC_CHANNEL, &adc_raw);
            }
            // แปลงค่า ADC (0-4095) เป็นแรงดันไฟฟ้าโดยประมาณ (0.00 - 3.30 V)
            float voltage = ((float)adc_raw / 4095.0f) * 3.3f;
            if (voltage > 3.3f) voltage = 3.3f;
            if (voltage < 0.0f) voltage = 0.0f;

            // ปัดเศษทศนิยม 2 ตำแหน่ง
            double voltage_rounded = (double)((int)(voltage * 100.0f + 0.5f)) / 100.0;

            // สร้าง JSON Payload ตามรูปแบบที่ Flutter Telemetry Dashboard คาดหวัง
            // ตัวอย่าง: {"voltage": 2.50, "raw": 3102, "uptime": 10}
            cJSON *root = cJSON_CreateObject();
            cJSON_AddNumberToObject(root, "voltage", voltage_rounded);
            cJSON_AddNumberToObject(root, "raw", adc_raw);
            cJSON_AddNumberToObject(root, "uptime", esp_log_timestamp() / 1000);

            char *json_str = cJSON_PrintUnformatted(root);
            if (json_str != NULL) {
                esp_mqtt_client_publish(s_mqtt_client, TOPIC_TELEMETRY, json_str, 0, 0, 0);
                free(json_str);
            }
            cJSON_Delete(root);
        }
    }
}

/* ========================================================
 * 4. ฟังก์ชันหลัก (app_main)
 * ======================================================== */
void app_main(void)
{
    // 1. กำหนดค่า NVS Flash สำหรับจัดเก็บการตั้งค่า Wi-Fi
    esp_err_t ret = nvs_flash_init();
    if (ret == ESP_ERR_NVS_NO_FREE_PAGES || ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        ret = nvs_flash_init();
    }
    ESP_ERROR_CHECK(ret);

    // 2. กำหนดค่า GPIO สำหรับหลอดไฟ LED (GPIO 2)
    gpio_reset_pin(LED_PIN);
    gpio_set_direction(LED_PIN, GPIO_MODE_OUTPUT);
    gpio_set_level(LED_PIN, 0);

    // 3. กำหนดค่า ADC สำหรับอ่าน Potentiometer บนขา GPIO 34 (ADC1_CH6)
    adc_oneshot_unit_init_cfg_t init_config = {
        .unit_id = ADC_UNIT_1,
    };
    adc_oneshot_new_unit(&init_config, &s_adc_handle);

    adc_oneshot_chan_cfg_t chan_config = {
        .bitwidth = ADC_BITWIDTH_DEFAULT,
        .atten = ADC_ATTEN_DB_12,
    };
    adc_oneshot_config_channel(s_adc_handle, ADC_CHANNEL, &chan_config);

    // 4. เริ่มการเชื่อมต่อ Wi-Fi และรอจนกว่าจะได้ IP Address
    wifi_init_sta();
    xEventGroupWaitBits(s_wifi_event_group, WIFI_CONNECTED_BIT, false, true, portMAX_DELAY);

    // 5. ตั้งค่า MQTT Client พร้อมกลไก LWT (Last Will and Testament)
    esp_mqtt_client_config_t mqtt_cfg = {
        .broker = {
            .address = {
                .uri = MQTT_BROKER_URI,
            },
        },
        .session = {
            .keepalive = 60,
            .last_will = {
                .topic = TOPIC_STATUS,
                .msg = "offline",
                .msg_len = 7,
                .qos = 1,
                .retain = 1,
            },
        },
    };

    s_mqtt_client = esp_mqtt_client_init(&mqtt_cfg);
    esp_mqtt_client_register_event(s_mqtt_client, ESP_EVENT_ANY_ID, mqtt_event_handler, NULL);
    esp_mqtt_client_start(s_mqtt_client);

    // 6. สร้าง FreeRTOS Task สำหรับส่งข้อมูล Telemetry ต่อเนื่อง
    xTaskCreate(telemetry_task, "telemetry_task", 4096, NULL, 5, NULL);
}
