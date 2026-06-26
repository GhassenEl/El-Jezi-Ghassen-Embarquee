import 'package:flutter_test/flutter_test.dart';
import 'package:smart_home/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smart Home affiche les onglets', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartHomeApp());
    await tester.pump();
    expect(find.text('Maison'), findsOneWidget);
    expect(find.text('Controles'), findsOneWidget);
    expect(find.text('Alertes'), findsOneWidget);
    expect(find.text('IA'), findsOneWidget);
  });
}
