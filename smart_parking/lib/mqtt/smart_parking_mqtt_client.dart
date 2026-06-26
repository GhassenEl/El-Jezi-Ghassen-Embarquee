import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

abstract final class SmartParkingTopics {
  static const telemetry = 'eljezi/parking/telemetry';
  static const command = 'eljezi/parking/command';
  static const status = 'eljezi/parking/status';
  static const alert = 'eljezi/parking/alert';
  static const clientId = 'ElJezi-Flutter-SmartParking';
}

class ParkingTelemetry {
  const ParkingTelemetry({
    required this.lotId,
    required this.spotsTotal,
    required this.spotsFree,
    required this.occupancyPct,
    required this.evFree,
    required this.gateOpen,
    required this.tempC,
    required this.humidity,
  });

  final String lotId;
  final int spotsTotal;
  final int spotsFree;
  final int occupancyPct;
  final int evFree;
  final bool gateOpen;
  final double tempC;
  final double humidity;

  static ParkingTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'LOT\s*=\s*([^,]+)\s*,\s*'
      r'SPOTS\s*=\s*(\d+)\s*,\s*'
      r'FREE\s*=\s*(\d+)\s*,\s*'
      r'OCC\s*=\s*(\d+)\s*,\s*'
      r'EV\s*=\s*(\d+)\s*,\s*'
      r'GATE\s*=\s*(\d)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return ParkingTelemetry(
      lotId: m.group(1)!.trim(),
      spotsTotal: int.tryParse(m.group(2)!) ?? 0,
      spotsFree: int.tryParse(m.group(3)!) ?? 0,
      occupancyPct: int.tryParse(m.group(4)!) ?? 0,
      evFree: int.tryParse(m.group(5)!) ?? 0,
      gateOpen: m.group(6) == '1',
      tempC: double.tryParse(m.group(7)!) ?? 0,
      humidity: double.tryParse(m.group(8)!) ?? 0,
    );
  }
}

class ParkingStatus {
  const ParkingStatus({
    required this.lotId,
    required this.online,
    required this.mode,
    required this.gateOpen,
  });

  final String lotId;
  final bool online;
  final String mode;
  final bool gateOpen;

  static ParkingStatus? tryParse(String raw) {
    final m = RegExp(
      r'LOT\s*=\s*([^,]+)\s*,\s*'
      r'ONLINE\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(\w+)\s*,\s*'
      r'GATE\s*=\s*(OPEN|CLOSED|\d)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    final gate = m.group(4)!.toUpperCase();
    return ParkingStatus(
      lotId: m.group(1)!.trim(),
      online: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
      gateOpen: gate == 'OPEN' || gate == '1',
    );
  }
}

class ParkingAlert {
  const ParkingAlert({required this.lotId, required this.alert});

  final String lotId;
  final String alert;

  static ParkingAlert? tryParse(String raw) {
    final m = RegExp(
      r'LOT\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*([\w_,.=]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return ParkingAlert(lotId: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

class SmartParkingMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<ParkingTelemetry>.broadcast();
  final _statusCtrl = StreamController<ParkingStatus>.broadcast();
  final _alertCtrl = StreamController<ParkingAlert>.broadcast();

  Stream<ParkingTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<ParkingStatus> get statusStream => _statusCtrl.stream;
  Stream<ParkingAlert> get alertStream => _alertCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();
    final client = MqttServerClient.withPort(host, SmartParkingTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartParkingTopics.clientId)
        .startClean();
    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker MQTT injoignable');
    }
    _client = client;
    client.subscribe(SmartParkingTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartParkingTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartParkingTopics.alert, MqttQos.atLeastOnce);
    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );
      if (topic == SmartParkingTopics.telemetry) {
        final t = ParkingTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (topic == SmartParkingTopics.status) {
        final s = ParkingStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (topic == SmartParkingTopics.alert) {
        final a = ParkingAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) throw StateError('Non connecte MQTT');
    final builder = MqttClientPayloadBuilder()..addString(command.trim().toUpperCase());
    client.publishMessage(SmartParkingTopics.command, MqttQos.atLeastOnce, builder.payload!);
  }

  Future<void> disconnect() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    _client?.disconnect();
    _client = null;
  }

  void dispose() {
    disconnect();
    _telemetryCtrl.close();
    _statusCtrl.close();
    _alertCtrl.close();
  }
}
