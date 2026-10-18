import 'package:flutter_test/flutter_test.dart';
import 'package:iot_mqtt_basics/main.dart';

void main() {
  testWidgets('Unified IoT app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const UnifiedIotApp());
    expect(find.byType(UnifiedIotApp), findsOneWidget);
  });
}
