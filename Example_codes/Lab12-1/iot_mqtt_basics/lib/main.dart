import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const MqttBasicsApp());
}

class MqttBasicsApp extends StatelessWidget {
  const MqttBasicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lab 12.1 MQTT Basics',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E676),
        ),
      ),
      home: const MqttBasicsScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MqttBasicsScreen extends StatefulWidget {
  const MqttBasicsScreen({super.key});

  @override
  State<MqttBasicsScreen> createState() => _MqttBasicsScreenState();
}

class _MqttBasicsScreenState extends State<MqttBasicsScreen> {
  // หมายเลข IP ของเครื่องคอมพิวเตอร์ที่รัน Mosquitto Broker
  final TextEditingController _brokerIpController = TextEditingController(
    text: '127.0.0.1',
  );

  MqttServerClient? _client;
  String _statusText = 'ยังไม่ได้เชื่อมต่อ (Disconnected)';
  Color _statusColor = Colors.redAccent;
  final List<String> _receivedLogs = [];

  @override
  void dispose() {
    _brokerIpController.dispose();
    _client?.disconnect();
    super.dispose();
  }

  Future<void> _connectToBroker() async {
    setState(() {
      _statusText = 'กำลังเชื่อมต่อไปยัง Broker...';
      _statusColor = Colors.amber;
    });

    final broker = _brokerIpController.text.trim();
    final clientId = 'Flutter_Lab12_1_${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient(broker, clientId);
    _client!.port = 1883;
    _client!.keepAlivePeriod = 20;
    _client!.autoReconnect = true;

    _client!.onConnected = () {
      setState(() {
        _statusText = 'เชื่อมต่อสำเร็จ (Connected)';
        _statusColor = const Color(0xFF00E676);
      });
      _subscribeToTestTopic();
    };

    _client!.onDisconnected = () {
      setState(() {
        _statusText = 'การเชื่อมต่อหลุด (Disconnected)';
        _statusColor = Colors.redAccent;
      });
    };

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillTopic('iot/flutter/lwt')
        .withWillMessage('Client crashed')
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      await _client!.connect();
    } on SocketException catch (e) {
      _appendLog('❌ Socket Error: ไม่สามารถต่อ Broker IP ได้ ($e)');
      _client?.disconnect();
    } catch (e) {
      _appendLog('❌ Error: $e');
      _client?.disconnect();
    }
  }

  void _disconnectFromBroker() {
    _client?.disconnect();
    _appendLog('ℹ️ ตัดการเชื่อมต่อเรียบร้อย');
  }

  void _subscribeToTestTopic() {
    const topic = 'test/broker/echo';
    _client?.subscribe(topic, MqttQos.atMostOnce);
    _appendLog('📢 Subscribed to: $topic');

    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final recMess = c[0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(
        recMess.payload.message,
      );
      _appendLog('📩 [${c[0].topic}] -> $pt');
    });
  }

  void _publishTestMessage() {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      _appendLog('⚠️ ไม่สามารถส่งข้อความได้เนื่องจากยังไม่ได้เชื่อมต่อ');
      return;
    }

    const topic = 'test/flutter/ping';
    final builder = MqttClientPayloadBuilder();
    builder.addString(
      'Hello from Flutter at ${DateTime.now().toIso8601String()}',
    );

    _client?.publishMessage(topic, MqttQos.atMostOnce, builder.payload!);

    _appendLog('🚀 Published -> $topic');
  }

  void _appendLog(String log) {
    setState(() {
      _receivedLogs.insert(
        0,
        '[${DateTime.now().toLocal().toString().substring(11, 19)}] $log',
      );
      if (_receivedLogs.length > 50) _receivedLogs.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lab 12.1: MQTT Client Basics'),
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ส่วนกรอก IP Broker
            TextField(
              controller: _brokerIpController,
              decoration: const InputDecoration(
                labelText: 'Broker IPv4 Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
            ),
            const SizedBox(height: 12),

            // แถบแสดงสถานะ
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _statusColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _statusColor),
              ),
              child: Row(
                children: [
                  Icon(Icons.circle, color: _statusColor, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    _statusText,
                    style: TextStyle(
                      color: _statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ปุ่มกดสั่งการ
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _connectToBroker,
                    icon: const Icon(Icons.link),
                    label: const Text('Connect'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E5FF),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _disconnectFromBroker,
                    icon: const Icon(Icons.link_off),
                    label: const Text('Disconnect'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _publishTestMessage,
                icon: const Icon(Icons.send),
                label: const Text('Publish Test Message (Ping)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // กล่องข้อความ Logs
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'บันทึกการทำงาน (Transaction Logs):',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: ListView.builder(
                  itemCount: _receivedLogs.length,
                  itemBuilder: (context, index) => Text(
                    _receivedLogs[index],
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
