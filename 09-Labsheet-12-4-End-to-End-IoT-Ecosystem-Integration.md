# ใบงานการทดลองที่ 12.4
### การทดสอบผสานรวมระบบครบวงจร (ESP32-C3 Hardware <-> Mosquitto Broker <-> Flutter Mobile App)

> [!NOTE] **คำชี้แจง**
> ในใบงานนี้นักศึกษาจะได้นำทุกจิ๊กซอว์ที่พัฒนามาตั้งแต่สัปดาห์ที่ 11 และสัปดาห์ที่ 12 มาร้อยเรียงทำงานร่วมกันเป็น **ระบบนิเวศ IoT แบบครบวงจร (Complete End-to-End IoT Ecosystem)** โดยบอร์ดฮาร์ดแวร์จริง ESP32-C3 จะสื่อสารกับแอปพลิเคชัน Flutter บนสมาร์ตโฟนผ่าน Mosquitto Broker เพื่อทดสอบการหมุนปรับค่า Potentiometer ทางกายภาพแล้วเห็นเข็มหน้าจอมือถือขยับทันที และการแตะสวิตช์บนมือถือแล้วหลอดไฟ LED จริงบนโต๊ะทดลองสว่างขึ้นในเสี้ยววินาที

---

## 1. วัตถุประสงค์การทดลอง
1. สามารถผสานรวมหน้าจอควบคุม Actuator และหน้าจอแสดงผล Telemetry เข้าเป็นแอปพลิเคชันรวมศูนย์ (Unified Multi-tab IoT App) ได้
2. สามารถเชื่อมต่อฮาร์ดแวร์บอร์ด ESP32-C3 เข้ากับ Mosquitto Broker และสื่อสารกับแอป Flutter ได้สำเร็จ
3. สามารถวัดและวิเคราะห์ความหน่วงเวลาตอบสนองแบบไป-กลับ (Round-Trip Time - RTT) ของคำสั่งควบคุมได้
4. สามารถทดสอบความทนทานต่อสภาวะเครือข่ายล้มเหลว (Fault-Tolerance & LWT Handling) ในสถานการณ์จริงได้

---

## 2. แผนผังการทดสอบระบบแบบครบวงจรและโครงสร้างหัวข้อ (End-to-End Pipeline & Topic Architecture)

<p align="center"><img src="Images/Lab12.4-1_academic.svg" ></p>

| ชื่อหัวข้อ (Topic) | ทิศทางการส่ง | ชนิดข้อมูล (Payload Format) | วัตถุประสงค์ |
| :--- | :--- | :--- | :--- |
| `iot/esp32/status` | ESP32 -> Broker (LWT) | Plaintext: `"online"` หรือ `"offline"` | ตัวบ่งชี้ความพร้อมทำงานของบอร์ดฮาร์ดแวร์ (LWT Retained) |
| `iot/esp32/control` | Flutter -> ESP32 | JSON: `{"led": "ON"}` หรือ `{"led": "OFF"}` | ส่งคำสั่งเปิด-ปิดหลอดไฟ LED จากสมาร์ตโฟน |
| `iot/esp32/led_ack` | ESP32 -> Flutter | JSON: `{"led_state": true, "ack": true}` | ส่งการตอบรับสถานะจริงทางกายภาพของหลอดไฟกลับมายังแอป |
| `iot/esp32/telemetry` | ESP32 -> Flutter | JSON: `{"voltage": 2.50, "raw": 3102, "uptime": 10}` | ส่งค่าแรงดันตรวจวัดจาก Potentiometer และ Uptime แบบเรียลไทม์ |

---

## 3. ขั้นตอนการทดลอง (Step-by-Step Activities)

### กิจกรรมที่ 12-4.1: การเตรียมโปรเจกต์และสร้างแอปพลิเคชันรวมศูนย์ (`lib/main.dart`)

#### 1. คัดลอกโปรเจกต์และรวบรวมคอมโพเนนต์
ในแล็บนี้เราจะนำหน้าจอ `actuator_control_screen.dart` จาก Lab 12-2 และหน้าจอ `telemetry_dashboard_screen.dart` พร้อมกับ `radial_gauge_widget.dart` จาก Lab 12-3 มารวมกัน:

**คำสั่ง PowerShell:**
```powershell
# 1. คัดลอกโฟลเดอร์โปรเจกต์จาก Lab12-3 มาเป็น Lab12-4
Copy-Item -Recurse -Path "..\Lab12-3\iot_telemetry_gauge" -Destination "..\Lab12-4\iot_unified_dashboard"

# 2. คัดลอกหน้าจอ Actuator Control Screen จาก Lab12-2 มารวมในโฟลเดอร์ lib/
Copy-Item -Path "..\Lab12-2\iot_actuator_switch\lib\actuator_control_screen.dart" -Destination "..\Lab12-4\iot_unified_dashboard\lib\"

# 3. ย้ายเข้าไปยังโฟลเดอร์โปรเจกต์ใหม่
cd ..\Lab12-4\iot_unified_dashboard

# 4. ล้างแคชการคอมไพล์เดิมออก
flutter clean
```
*(หรือใช้ File Explorer ในการคัดลอกโฟลเดอร์และไฟล์ตามขั้นตอนข้างต้น)*

#### 2. ปรับปรุงโค้ดรวมศูนย์แอปพลิเคชัน (`lib/main.dart`)
เปิดไฟล์ `lib/main.dart` แล้วแทนที่ด้วยโค้ดต่อไปนี้ ซึ่งใช้ `IndexedStack` ร่วมกับ `NavigationBar` เพื่อรักษาสถานะ (State) และการเชื่อมต่อ MQTT ของทั้ง 2 หน้าจอให้ทำงานต่อเนื่องโดยไม่ตัดการเชื่อมต่อเมื่อสลับแท็บ:

```dart
import 'package:flutter/material.dart';
import 'actuator_control_screen.dart';
import 'telemetry_dashboard_screen.dart';

void main() {
  runApp(const UnifiedIotApp());
}

class UnifiedIotApp extends StatelessWidget {
  const UnifiedIotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 Smart IoT Commander',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E676),
        ),
      ),
      home: const MainNavigationShell(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  // หมายเลข IP ของเครื่องรัน Broker:
  // - ใช้ '127.0.0.1' หากรันบนคอมพิวเตอร์เครื่องเดียวกัน (Windows Desktop) สำหรับการทดสอบจำลอง
  // - เปลี่ยนเป็น IP วง LAN ของเครื่องคอมพิวเตอร์ (เช่น '192.168.1.100') เมื่อรันแอปบนมือถือ หรือเชื่อมต่อกับ ESP32 จริง
  final String brokerIp = '127.0.0.1';

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      TelemetryDashboardScreen(brokerIp: brokerIp),
      ActuatorControlScreen(brokerIp: brokerIp),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ใช้ IndexedStack เพื่อรักษาสถานะและการเชื่อมต่อ MQTT ของทั้งสองหน้าจอให้ทำงานต่อเนื่อง
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        backgroundColor: const Color(0xFF1E293B),
        indicatorColor: const Color(0xFF00E5FF).withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed),
            selectedIcon: Icon(Icons.speed, color: Color(0xFF00E5FF)),
            label: 'Telemetry Gauge',
          ),
          NavigationDestination(
            icon: Icon(Icons.toggle_on_outlined),
            selectedIcon: Icon(Icons.toggle_on, color: Color(0xFF00E676)),
            label: 'Actuator Switch',
          ),
        ],
      ),
    );
  }
}
```

#### 3. สั่งรัน Flutter App
```powershell
# รันบน Windows Desktop
flutter run -d windows

# หรือรันบน Android Device / Emulator
flutter run -d <device-id>
```

> [!TIP]
> **การกำหนด Broker IP เมื่อทดสอบร่วมกับ ESP32 หรือสมาร์ตโฟนจริง:**  
> 1. ตรวจสอบหมายเลข IPv4 ของคอมพิวเตอร์ผ่าน PowerShell ด้วยคำสั่ง `ipconfig` (เช่น `192.168.1.105`)
> 2. แก้ไขตัวแปร `brokerIp = '192.168.1.105';` ใน `main.dart`
> 3. เปิดไฟล์ `mosquitto.conf` ที่มีคำสั่ง `listener 1883 0.0.0.0` และ `allow_anonymous true`
> 4. สตาร์ต Broker ด้วยคำสั่ง:
>    ```powershell
>    mosquitto -c mosquitto.conf -v
>    ```

---

### กิจกรรมที่ 12-4.2: การเตรียมและสตาร์ตเฟิร์มแวร์ ESP32-C3

#### 1. การต่อวงจรฮาร์ดแวร์บนเบรดบอร์ด (Circuit Wiring)
- **Potentiometer (เซนเซอร์แอนะล็อก):**
  - ขาริมซ้าย: ต่อเข้าขา `3.3V` ของ ESP32-C3
  - ขาริมขวา: ต่อเข้าขา `GND` ของ ESP32-C3
  - ขากลาง (สัญญาณ): ต่อเข้าขา `GPIO 0` (ช่องต่อ ADC1_CH0)
- **หลอดไฟ LED ทดสอบ (ตัวกระทำ):**
  - ขา Anode (+) ยาว: ต่อผ่านตัวต้านทาน `330Ω` เข้าขา `GPIO 8`
  - ขา Cathode (-) สั้น: ต่อเข้าขา `GND`

#### 2. การกำหนดค่าและแฟลชเฟิร์มแวร์
1. เปิดโปรเจกต์ `Lab11-2_MQTT_Client` จากสัปดาห์ที่ 11
2. ตรวจสอบและกำหนดค่าในไฟล์ `main/main.c`:
   * กำหนด SSID และรหัสผ่าน Wi-Fi ให้เชื่อมต่อเครือข่ายเดียวกับคอมพิวเตอร์
   * กำหนด Broker IP ชี้ไปยังหมายเลข IP ของคอมพิวเตอร์ของคุณ
   * มีการ Publish ค่าแรงดันแอนะล็อก (GPIO 0) ไปยัง `iot/esp32/telemetry` ทุก 500 ms ในรูปแบบ JSON: `{"voltage": 2.50, "raw": 3102, "uptime": 10}`
   * มีการ Subscribe หัวข้อ `iot/esp32/control` และสั่งเปลี่ยนระดับสัญญาณบนขา GPIO 8 ตามค่า `"ON"` หรือ `"OFF"`
   * มีการ Publish ข้อความยืนยันไปยัง `iot/esp32/led_ack` ในรูปแบบ JSON: `{"led_state": true, "ack": true}` เมื่อเปลี่ยนสถานะสำเร็จ
   * มีการกำหนด Last Will and Testament (LWT) ไปยัง `iot/esp32/status` ด้วยข้อความ `"offline"` (Retain = true)
3. สั่งคอมไพล์และแฟลชเฟิร์มแวร์ลงบอร์ด ESP32-C3:
```powershell
idf.py flash monitor
```

---

### กิจกรรมที่ 12-4.3: การทดสอบ 4 กรณีทดสอบวิกฤต (Verification Test Matrix)

ให้นักศึกษาทำการทดสอบระบบครบวงจรและบันทึกผลการทดลองลงในตาราง:

| รายการทดสอบ | การกระทำเชิงกายภาพ (Hardware Action) | พฤติกรรมที่คาดหวังบน Flutter App | ผลการทดลองจริง (ผ่าน/ไม่ผ่าน) |
| :--- | :--- | :--- | :--- |
| **Test Case 1: Telemetry Monitoring** | ใช้ไขควงหมุน Potentiometer จากซ้ายสุดไปขวาสุด | เข็มบน Radial Gauge หมุนจาก 0.0V ไปหา 3.3V อย่างนุ่มนวล ค่าดิบ ADC เปลี่ยนแปลง และกราฟประวัติ Live Sparkline ขยับต่อเนื่อง | |
| **Test Case 2: Actuator Remote Control** | แตะสวิตช์บนแอปเพื่อเปิดไฟ LED | หลอดไฟ LED บนเบรดบอร์ดติดสว่างทันที สวิตช์และไอคอนบนแอปเรืองแสงสีเขียว พร้อมการสั่นตอบสนอง (Haptic Feedback) | |
| **Test Case 3: State Sync & Physical ACK** | ปลดสายหรือสลับสถานะหลอดไฟโดยตรง หรือส่งสัญญาณ ACK หลอก | แอปพลิเคชันได้รับค่า ACK และปรับปรุงสวิตช์ตามความเป็นจริง หากไม่ได้รับ ACK สวิตช์จะไม่อัปเดตสถานะคงที่ | |
| **Test Case 4: Fault Tolerance (LWT)** | ถอดสาย USB จ่ายไฟของบอร์ด ESP32 ออกกะทันหัน | ภายใน 20–30 วินาที ป้ายสถานะฮาร์ดแวร์บนแอปต้องเปลี่ยนเป็น "OFFLINE" สีแดง และสวิตช์สั่งการจะถูกปิดกั้นไม่ให้ส่งคำสั่ง | |

> [!TIP]
> **แนวทางการจำลองการทดสอบผ่าน PowerShell (Mock Simulation Fallback):**  
> หากยังไม่ได้ต่อบอร์ด ESP32 จริง สามารถเปิด PowerShell อีกหน้าต่างเพื่อทดสอบจำลองแต่ละ Test Case ได้ดังนี้:
> - **จำลอง Test Case 1 (Telemetry):**
>   ```powershell
>   mosquitto_pub -h 127.0.0.1 -p 1883 -t "iot/esp32/telemetry" -m '{"voltage": 2.10, "raw": 2608, "uptime": 45}'
>   ```
> - **จำลอง Test Case 2 (รับคำสั่งควบคุม):**
>   ```powershell
>   mosquitto_sub -h 127.0.0.1 -p 1883 -t "iot/esp32/control" -v
>   ```
> - **จำลอง Test Case 3 (ส่ง ACK ยืนยันกลับ):**
>   ```powershell
>   mosquitto_pub -h 127.0.0.1 -p 1883 -t "iot/esp32/led_ack" -m '{"led_state": true, "ack": true}'
>   ```
> - **จำลอง Test Case 4 (จำลอง LWT ออฟไลน์):**
>   ```powershell
>   mosquitto_pub -h 127.0.0.1 -p 1883 -t "iot/esp32/status" -m "offline" -r
>   ```

---

### กิจกรรมที่ 12-4.4: การวัดความหน่วงเวลาในการควบคุม (Control Latency Benchmark)

1. วัดเวลาตั้งแต่แตะสวิตช์ในแอป จนกระทั่งได้รับข้อความยืนยัน `iot/esp32/led_ack` กลับมายังสมาร์ตโฟน (Round-Trip Time - RTT)
2. สังเกตความหน่วงและบันทึกผลเปรียบเทียบในตาราง:

| สภาพแวดล้อมเครือข่าย | ประเภทการเชื่อมต่อ | เวลาตอบสนองโดยเฉลี่ย (RTT: ms) | ความเสถียร / ข้อสังเกต |
| :--- | :--- | :--- | :--- |
| **Local Wi-Fi LAN** | สมาร์ตโฟนและบอร์ด ESP32 ต่อเข้ากับ Wi-Fi Router เดียวกันในห้องทดลอง | ประมาณ 20 – 60 ms | รวดเร็ว ตอบสนองแทบจะทันที |
| **Mobile Hotspot / 4G** | สมาร์ตโฟนเชื่อมต่อ 4G/5G ชี้มายัง Broker ผ่าน Public IP หรือ Tailscale/VPN | ประมาณ 80 – 250 ms | ขึ้นอยู่กับความแรงสัญญาณและ Routing |

---

## 4. สรุปผลและคำถามท้ายบทเรียน
1. เหตุใดการใช้ `IndexedStack` ใน `MainNavigationShell` จึงมีความสำคัญอย่างยิ่งสำหรับแอปพลิเคชัน IoT แบบ Multi-tab เมื่อเทียบกับการสลับวิดเจ็ตด้วย `body: _pages[_currentIndex]`?
2. เมื่อเปรียบเทียบการพัฒนาด้วย Flutter ในสัปดาห์นี้ กับการเปิดหน้าเว็บ HTTP บนเบราว์เซอร์ในสัปดาห์ที่ 8-10 ข้อใดให้ประสบการณ์การใช้งาน (UX) และความเสถียรที่ดีกว่าเมื่อข้อมูลเซนเซอร์มาด้วยความถี่สูง? เพราะเหตุใด?
3. หากต้องการนำแอปพลิเคชันนี้ไปเผยแพร่จริงบน Google Play Store หรือ Apple App Store ขั้นตอนความปลอดภัยที่ต้องปรับปรุงเพิ่มเติมมีอะไรบ้าง? (พิจารณาเรื่อง MQTTS / TLS พอร์ต 8883, การเข้ารหัส Token ยืนยันตัวตน, และการเก็บรักษา Credential)
