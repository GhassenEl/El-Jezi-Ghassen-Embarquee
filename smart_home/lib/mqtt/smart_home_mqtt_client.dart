import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

abstract final class SmartHomeTopics {
  static const telemetry = 'eljezi/home/telemetry';
  static const command = 'eljezi/home/command';
  static const status = 'eljezi/home/status';
  static const alert = 'eljezi/home/alert';
  static const clientId = 'ElJezi-Flutter-SmartHome';
}

class HomeTelemetry {
  const HomeTelemetry({
    required this.zone,
    required this.tempC,
    required this.humidity,
    required this.lux,
    required this.motion,
    required this.doorOpen,
    required this.lightOn,
    required this.heatOn,
    required this.powerW,
  });

  final String zone;
  final double tempC;
  final double humidity;
  final int lux;
  final bool motion;
  final bool doorOpen;
  final bool lightOn;
  final bool heatOn;
  final int powerW;

  static HomeTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)\s*,\s*'
      r'LUX\s*=\s*(\d+)\s*,\s*'
      r'MOTION\s*=\s*(\d)\s*,\s*'
      r'DOOR\s*=\s*(\d)\s*,\s*'
      r'LIGHT\s*=\s*(\d)\s*,\s*'
      r'HEAT\s*=\s*(\d)\s*,\s*'
      r'PWR\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return HomeTelemetry(
      zone: m.group(1)!.trim(),
      tempC: double.tryParse(m.group(2)!) ?? 0,
      humidity: double.tryParse(m.group(3)!) ?? 0,
      lux: int.tryParse(m.group(4)!) ?? 0,
      motion: m.group(5) == '1',
      doorOpen: m.group(6) == '1',
      lightOn: m.group(7) == '1',
      heatOn: m.group(8) == '1',
      powerW: int.tryParse(m.group(9)!) ?? 0,
    );
  }
}

class HomeStatus {
  const HomeStatus({
    required this.zone,
    required this.online,
    required this.mode,
    required this.targetTemp,
    required this.alarmOn,
    required this.doorLocked,
  });

  final String zone;
  final bool online;
  final String mode;
  final double targetTemp;
  final bool alarmOn;
  final bool doorLocked;

  static HomeStatus? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*'
      r'ONLINE\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(HOME|AWAY|SLEEP)\s*,\s*'
      r'TARGET_T\s*=\s*([-.\d]+)\s*,\s*'
      r'ALARM\s*=\s*(\d)\s*,\s*'
      r'LOCK\s*=\s*(\d)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return HomeStatus(
      zone: m.group(1)!.trim(),
      online: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
      targetTemp: double.tryParse(m.group(4)!) ?? 22,
      alarmOn: m.group(5) == '1',
      doorLocked: m.group(6) == '1',
    );
  }
}

class HomeAlert {
  const HomeAlert({required this.zone, required this.alert});

  final String zone;
  final String alert;

  static HomeAlert? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*([\w_,.=]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return HomeAlert(zone: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

class SmartHomeMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<HomeTelemetry>.broadcast();
  final _statusCtrl = StreamController<HomeStatus>.broadcast();
  final _alertCtrl = StreamController<HomeAlert>.broadcast();

  Stream<HomeTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<HomeStatus> get statusStream => _statusCtrl.stream;
  Stream<HomeAlert> get alertStream => _alertCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();

    final client = MqttServerClient.withPort(host, SmartHomeTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartHomeTopics.clientId)
        .startClean();

    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker MQTT injoignable');
    }

    _client = client;
    client.subscribe(SmartHomeTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartHomeTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartHomeTopics.alert, MqttQos.atLeastOnce);
    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );
      if (topic == SmartHomeTopics.telemetry) {
        final t = HomeTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (topic == SmartHomeTopics.status) {
        final s = HomeStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (topic == SmartHomeTopics.alert) {
        final a = HomeAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) throw StateError('Non connecte MQTT');
    final builder = MqttClientPayloadBuilder()..addString(command.trim().toUpperCase());
    client.publishMessage(SmartHomeTopics.command, MqttQos.atLeastOnce, builder.payload!);
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
