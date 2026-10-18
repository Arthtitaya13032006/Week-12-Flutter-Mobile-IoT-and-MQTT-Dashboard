import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class ActuatorControlScreen extends StatefulWidget {
  final String brokerIp;
  const ActuatorControlScreen({super.key, required this.brokerIp});

  @override
  State<ActuatorControlScreen> createState() => _ActuatorControlScreenState();
}

class _ActuatorControlScreenState extends State<ActuatorControlScreen> {
  MqttServerClient? _client;
  bool _isLedOn = false;
  bool _isDeviceOnline = false;
  bool _isWaitingAck = false;
  String _networkStatus = 'กำลังเชื่อมต่อ Broker...';

  @override
  void initState() {
    super.initState();
    _connectMqtt();
  }

  @override
  void dispose() {
    _client?.disconnect();
    super.dispose();
  }

  Future<void> _connectMqtt() async {
    final clientId = 'Flutter_Switch_${DateTime.now().millisecondsSinceEpoch}';
    _client = MqttServerClient(widget.brokerIp, clientId);
    _client!.port = 1883;
    _client!.keepAlivePeriod = 20;

    _client!.onConnected = () {
      setState(() => _networkStatus = 'เชื่อมต่อ Broker เรียบร้อย');
      _subscribeTopics();
    };

    _client!.onDisconnected = () {
      setState(() {
        _networkStatus = 'ขาดการเชื่อมต่อ Broker!';
        _isDeviceOnline = false;
      });
    };

    try {
      await _client!.connect();
    } catch (e) {
      setState(() => _networkStatus = 'เชื่อมต่อล้มเหลว: $e');
    }
  }

  void _subscribeTopics() {
    // 1. บอกรับหัวข้อสถานะบอร์ด (LWT)
    _client?.subscribe('iot/esp32/status', MqttQos.atMostOnce);
    // 2. บอกรับหัวข้อยืนยันการทำงานของหลอดไฟ
    _client?.subscribe('iot/esp32/led_ack', MqttQos.atMostOnce);

    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      final topic = c[0].topic;

      setState(() {
        if (topic == 'iot/esp32/status') {
          _isDeviceOnline = (pt.trim().toLowerCase() == 'online');
        } else if (topic == 'iot/esp32/led_ack') {
          _isWaitingAck = false;
          try {
            final data = jsonDecode(pt);
            _isLedOn = data['led_state'] == true;
          } catch (_) {}
        }
      });
    });
  }

  void _toggleLed(bool targetState) {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ กรุณาเชื่อมต่อ Broker ก่อนสั่งการ')),
      );
      return;
    }

    if (!_isDeviceOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ อุปกรณ์ ESP32 ออฟไลน์อยู่ ไม่สามารถส่งคำสั่งได้'),
        ),
      );
      return;
    }

    // แตะแล้วสั่งสั่น Haptic Feedback
    HapticFeedback.lightImpact();

    setState(() {
      _isWaitingAck = true;
    });

    final payloadMap = {'led': targetState ? 'ON' : 'OFF'};
    final jsonStr = jsonEncode(payloadMap);
    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonStr);

    _client?.publishMessage(
      'iot/esp32/control',
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Actuator Control Center'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // แถบแสดงสถานะ Device Online/Offline
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _isDeviceOnline
                    ? const Color(0x1A00E676)
                    : const Color(0x1AFF5252),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isDeviceOnline
                      ? const Color(0xFF00E676)
                      : const Color(0xFFFF5252),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: _isDeviceOnline
                        ? const Color(0xFF00E676)
                        : const Color(0xFFFF5252),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isDeviceOnline
                        ? 'ESP32 ฮาร์ดแวร์: ออนไลน์ (ONLINE)'
                        : 'ESP32 ฮาร์ดแวร์: ออฟไลน์ (OFFLINE)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isDeviceOnline
                          ? const Color(0xFF00E676)
                          : const Color(0xFFFF5252),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // การ์ดควบคุมหลอดไฟแบบ Glassmorphism
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B).withOpacity(0.8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isLedOn
                      ? const Color(0xFF00E676).withOpacity(0.6)
                      : Colors.white12,
                  width: 2,
                ),
                boxShadow: _isLedOn
                    ? [
                        BoxShadow(
                          color: const Color(0xFF00E676).withOpacity(0.25),
                          blurRadius: 24,
                          spreadRadius: 4,
                        ),
                      ]
                    : [],
              ),
              child: Column(
                children: [
                  // ไอคอนหลอดไฟพร้อมเอฟเฟกต์แสง
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isLedOn
                          ? const Color(0x3300E676)
                          : Colors.black26,
                    ),
                    child: Icon(
                      Icons.lightbulb,
                      size: 72,
                      color: _isLedOn
                          ? const Color(0xFF00E676)
                          : Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'หลอดไฟ LED ทดสอบ (GPIO 2)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isWaitingAck
                        ? 'กำลังรอการยืนยันจากบอร์ด (Waiting ACK)...'
                        : _isLedOn
                        ? 'สถานะ: เปิดสว่าง (Active)'
                        : 'สถานะ: ปิดการทำงาน (Standby)',
                    style: TextStyle(
                      color: _isWaitingAck
                          ? Colors.amber
                          : (_isLedOn
                                ? const Color(0xFF00E676)
                                : Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // สวิตช์ควบคุม
                  Transform.scale(
                    scale: 1.4,
                    child: Switch(
                      value: _isLedOn,
                      activeColor: const Color(0xFF00E676),
                      onChanged: _isWaitingAck ? null : _toggleLed,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              _networkStatus,
              style: const TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }
}
