idf_component_register(SRCS "main.c"
                    INCLUDE_DIRS "."
                    REQUIRES mqtt cjson esp_wifi esp_event nvs_flash esp_adc driver esp_driver_gpio)
