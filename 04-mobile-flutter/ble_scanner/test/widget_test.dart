import 'package:flutter_test/flutter_test.dart';
import 'package:ble_scanner/main.dart';

void main() {
  testWidgets('Scanner affiche le titre', (tester) async {
    await tester.pumpWidget(const BleScannerApp());
    expect(find.text('El Jezi — BLE Scanner'), findsOneWidget);
    expect(find.text('Scanner'), findsOneWidget);
  });
}
