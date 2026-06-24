import 'package:flutter_test/flutter_test.dart';
import 'package:sensor_dashboard/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dashboard affiche les KPI', (tester) async {
    await tester.pumpWidget(const SensorDashboardApp());
    expect(find.text('El Jezi — Capteurs'), findsOneWidget);
    expect(find.text('T°'), findsOneWidget);
    expect(find.textContaining('Connecter ESP32'), findsOneWidget);
  });
}
