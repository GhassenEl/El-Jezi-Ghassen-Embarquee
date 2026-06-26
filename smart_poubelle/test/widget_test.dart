import 'package:flutter_test/flutter_test.dart';
import 'package:smart_poubelle/main.dart';

void main() {
  testWidgets('Smart Poubelle demarre', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartPoubelleApp());
    expect(find.text('El Jezi — Smart Poubelle'), findsOneWidget);
  });
}
