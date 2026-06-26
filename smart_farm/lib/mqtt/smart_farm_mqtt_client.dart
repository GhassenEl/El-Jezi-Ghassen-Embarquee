import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Protocole MQTT Smart Farm (voir 09-smart-farm).
abstract final class SmartFarmTopics {
  static const telemetry = 'eljezi/smartfarm/telemetry';
  static const command = 'eljezi/smartfarm/command';
  static const status = 'eljezi/smartfarm/status';
  static const alert = 'eljezi/smartfarm/alert';
  static const clientId = 'ElJezi-Flutter-SmartFarm';
}

class FarmTelemetry {
  const FarmTelemetry({
    required this.zone,
    required this.airTemp,
    required this.airHum,
    required this.soilMoist,
    required this.lightLux,
    required this.pumpOn,
    required this.mode,
  });

  final String zone;
  final double airTemp;
  final double airHum;
  final double soilMoist;
  final int lightLux;
  final bool pumpOn;
  final String mode;

  static FarmTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)\s*,\s*'
      r'S\s*=\s*([-.\d]+)\s*,\s*'
      r'L\s*=\s*(\d+)\s*,\s*'
      r'PUMP\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(AUTO|MANUAL)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return FarmTelemetry(
      zone: m.group(1)!.trim(),
      airTemp: double.tryParse(m.group(2)!) ?? 0,
      airHum: double.tryParse(m.group(3)!) ?? 0,
      soilMoist: double.tryParse(m.group(4)!) ?? 0,
      lightLux: int.tryParse(m.group(5)!) ?? 0,
      pumpOn: m.group(6) == '1',
      mode: m.group(7)!.toUpperCase(),
    );
  }
}

class FarmStatus {
  const FarmStatus({
    required this.zone,
    required this.pumpOn,
    required this.mode,
    required this.soilThresh,
  });

  final String zone;
  final bool pumpOn;
  final String mode;
  final int soilThresh;

  static FarmStatus? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*'
      r'PUMP\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(AUTO|MANUAL)\s*,\s*'
      r'THRESH\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return FarmStatus(
      zone: m.group(1)!.trim(),
      pumpOn: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
      soilThresh: int.tryParse(m.group(4)!) ?? 30,
    );
  }
}

class FarmAlert {
  const FarmAlert({required this.zone, required this.alert});

  final String zone;
  final String alert;

  static FarmAlert? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*(\w+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return FarmAlert(zone: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

/// Client MQTT Smart Farm.
class SmartFarmMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<FarmTelemetry>.broadcast();
  final _statusCtrl = StreamController<FarmStatus>.broadcast();
  final _alertCtrl = StreamController<FarmAlert>.broadcast();
  final _connectionCtrl = StreamController<bool>.broadcast();

  Stream<FarmTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<FarmStatus> get statusStream => _statusCtrl.stream;
  Stream<FarmAlert> get alertStream => _alertCtrl.stream;
  Stream<bool> get connectionStream => _connectionCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();

    final client = MqttServerClient.withPort(host, SmartFarmTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartFarmTopics.clientId)
        .startClean();

    try {
      await client.connect();
    } on Exception catch (e) {
      client.disconnect();
      throw StateError('Connexion MQTT impossible : $e');
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      final state = client.connectionStatus?.state;
      client.disconnect();
      throw StateError('Broker MQTT injoignable ($state)');
    }

    _client = client;
    _connectionCtrl.add(true);

    client.subscribe(SmartFarmTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartFarmTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartFarmTopics.alert, MqttQos.atLeastOnce);

    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );

      if (topic == SmartFarmTopics.telemetry) {
        final t = FarmTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (topic == SmartFarmTopics.status) {
        final s = FarmStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (topic == SmartFarmTopics.alert) {
        final a = FarmAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) {
      throw StateError('Non connecté au broker MQTT');
    }
    final cmd = command.trim().toUpperCase();
    final builder = MqttClientPayloadBuilder()..addString(cmd);
    client.publishMessage(
      SmartFarmTopics.command,
      MqttQos.atLeastOnce,
      builder.payload!,
    );
  }

  Future<void> disconnect() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        client.disconnect();
      } catch (_) {}
      _connectionCtrl.add(false);
    }
  }

  void dispose() {
    disconnect();
    _telemetryCtrl.close();
    _statusCtrl.close();
    _alertCtrl.close();
    _connectionCtrl.close();
  }
}
