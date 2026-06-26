import 'package:flutter_test/flutter_test.dart';
import 'package:smart_parking/main.dart';

void main() {
  testWidgets('Smart Parking demarre', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartParkingApp());
    expect(find.text('El Jezi — Smart Parking'), findsOneWidget);
  });
}
