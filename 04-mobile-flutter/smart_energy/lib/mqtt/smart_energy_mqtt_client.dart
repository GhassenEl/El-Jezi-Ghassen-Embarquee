import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

abstract final class SmartEnergyTopics {
  static const telemetry = 'eljezi/energy/telemetry';
  static const command = 'eljezi/energy/command';
  static const status = 'eljezi/energy/status';
  static const alert = 'eljezi/energy/alert';
  static const clientId = 'ElJezi-Flutter-SmartEnergy';
}

class EnergyTelemetry {
  const EnergyTelemetry({
    required this.siteId,
    required this.loadKw,
    required this.solarKw,
    required this.gridKw,
    required this.batteryPct,
    required this.costTndH,
    required this.peak,
    required this.tempC,
    required this.humidity,
  });

  final String siteId;
  final double loadKw;
  final double solarKw;
  final double gridKw;
  final int batteryPct;
  final double costTndH;
  final bool peak;
  final double tempC;
  final double humidity;

  static EnergyTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'SITE\s*=\s*([^,]+)\s*,\s*'
      r'LOAD\s*=\s*([-.\d]+)\s*,\s*'
      r'SOLAR\s*=\s*([-.\d]+)\s*,\s*'
      r'GRID\s*=\s*([-.\d]+)\s*,\s*'
      r'BATT\s*=\s*(\d+)\s*,\s*'
      r'COST\s*=\s*([-.\d]+)\s*,\s*'
      r'PEAK\s*=\s*(\d)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return EnergyTelemetry(
      siteId: m.group(1)!.trim(),
      loadKw: double.tryParse(m.group(2)!) ?? 0,
      solarKw: double.tryParse(m.group(3)!) ?? 0,
      gridKw: double.tryParse(m.group(4)!) ?? 0,
      batteryPct: int.tryParse(m.group(5)!) ?? 0,
      costTndH: double.tryParse(m.group(6)!) ?? 0,
      peak: m.group(7) == '1',
      tempC: double.tryParse(m.group(8)!) ?? 0,
      humidity: double.tryParse(m.group(9)!) ?? 0,
    );
  }
}

class EnergyStatus {
  const EnergyStatus({
    required this.siteId,
    required this.online,
    required this.mode,
    required this.gridConnected,
  });

  final String siteId;
  final bool online;
  final String mode;
  final bool gridConnected;

  static EnergyStatus? tryParse(String raw) {
    final m = RegExp(
      r'SITE\s*=\s*([^,]+)\s*,\s*'
      r'ONLINE\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(\w+)\s*,\s*'
      r'GRID\s*=\s*(\d)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return EnergyStatus(
      siteId: m.group(1)!.trim(),
      online: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
      gridConnected: m.group(4) == '1',
    );
  }
}

class EnergyAlert {
  const EnergyAlert({required this.siteId, required this.alert});

  final String siteId;
  final String alert;

  static EnergyAlert? tryParse(String raw) {
    final m = RegExp(
      r'SITE\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*([\w_,.=]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return EnergyAlert(siteId: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

class SmartEnergyMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<EnergyTelemetry>.broadcast();
  final _statusCtrl = StreamController<EnergyStatus>.broadcast();
  final _alertCtrl = StreamController<EnergyAlert>.broadcast();

  Stream<EnergyTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<EnergyStatus> get statusStream => _statusCtrl.stream;
  Stream<EnergyAlert> get alertStream => _alertCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();
    final client = MqttServerClient.withPort(host, SmartEnergyTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartEnergyTopics.clientId)
        .startClean();
    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker MQTT injoignable');
    }
    _client = client;
    client.subscribe(SmartEnergyTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartEnergyTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartEnergyTopics.alert, MqttQos.atLeastOnce);
    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );
      if (topic == SmartEnergyTopics.telemetry) {
        final t = EnergyTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (topic == SmartEnergyTopics.status) {
        final s = EnergyStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (topic == SmartEnergyTopics.alert) {
        final a = EnergyAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) throw StateError('Non connecte MQTT');
    final builder = MqttClientPayloadBuilder()..addString(command.trim().toUpperCase());
    client.publishMessage(SmartEnergyTopics.command, MqttQos.atLeastOnce, builder.payload!);
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
