import 'package:flutter_test/flutter_test.dart';
import 'package:iot_remote/main.dart';

void main() {
  testWidgets('Remote affiche les commandes', (tester) async {
    await tester.pumpWidget(const IotRemoteApp());
    expect(find.text('El Jezi — IoT Remote'), findsOneWidget);
    expect(find.text('LED embarquée'), findsOneWidget);
  });
}
