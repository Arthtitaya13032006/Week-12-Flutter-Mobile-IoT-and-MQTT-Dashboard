import 'package:flutter_test/flutter_test.dart';
import 'package:iot_mqtt_basics/main.dart';

void main() {
  testWidgets('Telemetry dashboard smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TelemetryApp());
    expect(find.byType(TelemetryApp), findsOneWidget);
  });
}
