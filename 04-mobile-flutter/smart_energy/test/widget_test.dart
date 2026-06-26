import 'package:flutter_test/flutter_test.dart';
import 'package:smart_energy/main.dart';

void main() {
  testWidgets('Smart Energy demarre', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartEnergyApp());
    expect(find.text('El Jezi — Smart Energy'), findsOneWidget);
  });
}
