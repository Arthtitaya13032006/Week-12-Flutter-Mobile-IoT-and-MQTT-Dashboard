import 'package:flutter/material.dart';
import 'telemetry_dashboard_screen.dart';

void main() {
  runApp(const TelemetryApp());
}

class TelemetryApp extends StatelessWidget {
  const TelemetryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lab 12.3 Telemetry Dashboard',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF00E676),
        ),
      ),
      // กำหนด IP ของ Mosquitto Broker (ใช้ 127.0.0.1 หากรันบนคอมพิวเตอร์เครื่องเดียวกัน)
      home: const TelemetryDashboardScreen(brokerIp: '127.0.0.1'),
      debugShowCheckedModeBanner: false,
    );
  }
}
