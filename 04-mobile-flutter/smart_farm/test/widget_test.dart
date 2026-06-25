import 'package:flutter_test/flutter_test.dart';
import 'package:smart_farm/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Smart Farm affiche les capteurs', (tester) async {
    await tester.pumpWidget(const SmartFarmApp());
    expect(find.text('El Jezi — Smart Farm'), findsOneWidget);
    expect(find.text('Humidité du sol'), findsOneWidget);
    expect(find.text('Broker Mosquitto'), findsOneWidget);
  });
}
