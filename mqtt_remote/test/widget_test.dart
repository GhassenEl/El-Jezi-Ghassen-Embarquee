import 'package:flutter_test/flutter_test.dart';
import 'package:mqtt_remote/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('MQTT Remote affiche les commandes', (tester) async {
    await tester.pumpWidget(const MqttRemoteApp());
    expect(find.text('El Jezi — MQTT Remote'), findsOneWidget);
    expect(find.text('LED embarquée'), findsOneWidget);
    expect(find.text('Broker Mosquitto'), findsOneWidget);
  });
}
