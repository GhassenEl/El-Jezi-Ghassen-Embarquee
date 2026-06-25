import 'package:flutter_test/flutter_test.dart';

import 'package:smart_station/main.dart';

void main() {
  testWidgets('Smart Station affiche les onglets', (WidgetTester tester) async {
    await tester.pumpWidget(const SmartStationApp());
    await tester.pump();
    expect(find.text('Arrivees'), findsOneWidget);
    expect(find.text('Lignes'), findsOneWidget);
    expect(find.text('Alertes'), findsOneWidget);
    expect(find.text('IA'), findsOneWidget);
  });
}
