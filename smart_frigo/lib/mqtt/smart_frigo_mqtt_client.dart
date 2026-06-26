import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

abstract final class SmartFrigoTopics {
  static const telemetry = 'eljezi/frigo/telemetry';
  static const command = 'eljezi/frigo/command';
  static const status = 'eljezi/frigo/status';
  static const alert = 'eljezi/frigo/alert';
  static const clientId = 'ElJezi-Flutter-SmartFrigo';
}

class FrigoTelemetry {
  const FrigoTelemetry({
    required this.zone,
    required this.fridgeTemp,
    required this.freezerTemp,
    required this.humidity,
    required this.doorOpen,
    required this.compressorOn,
    required this.powerW,
  });

  final String zone;
  final double fridgeTemp;
  final double freezerTemp;
  final double humidity;
  final bool doorOpen;
  final bool compressorOn;
  final int powerW;

  static FrigoTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'F\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)\s*,\s*'
      r'DOOR\s*=\s*(\d)\s*,\s*'
      r'COMP\s*=\s*(\d)\s*,\s*'
      r'PWR\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return FrigoTelemetry(
      zone: m.group(1)!.trim(),
      fridgeTemp: double.tryParse(m.group(2)!) ?? 0,
      freezerTemp: double.tryParse(m.group(3)!) ?? 0,
      humidity: double.tryParse(m.group(4)!) ?? 0,
      doorOpen: m.group(5) == '1',
      compressorOn: m.group(6) == '1',
      powerW: int.tryParse(m.group(7)!) ?? 0,
    );
  }
}

class FrigoStatus {
  const FrigoStatus({
    required this.zone,
    required this.online,
    required this.mode,
    required this.targetFridge,
    required this.targetFreezer,
    required this.alarmOn,
  });

  final String zone;
  final bool online;
  final String mode;
  final double targetFridge;
  final double targetFreezer;
  final bool alarmOn;

  static FrigoStatus? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*'
      r'ONLINE\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(NORMAL|ECO)\s*,\s*'
      r'TARGET_F\s*=\s*([-.\d]+)\s*,\s*'
      r'TARGET_Z\s*=\s*([-.\d]+)\s*,\s*'
      r'ALARM\s*=\s*(\d)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return FrigoStatus(
      zone: m.group(1)!.trim(),
      online: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
      targetFridge: double.tryParse(m.group(4)!) ?? 4,
      targetFreezer: double.tryParse(m.group(5)!) ?? -18,
      alarmOn: m.group(6) == '1',
    );
  }
}

class FrigoAlert {
  const FrigoAlert({required this.zone, required this.alert});
  final String zone;
  final String alert;

  static FrigoAlert? tryParse(String raw) {
    final m = RegExp(
      r'ZONE\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*([\w_,.=]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return FrigoAlert(zone: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

class SmartFrigoMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<FrigoTelemetry>.broadcast();
  final _statusCtrl = StreamController<FrigoStatus>.broadcast();
  final _alertCtrl = StreamController<FrigoAlert>.broadcast();

  Stream<FrigoTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<FrigoStatus> get statusStream => _statusCtrl.stream;
  Stream<FrigoAlert> get alertStream => _alertCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();
    final client = MqttServerClient.withPort(host, SmartFrigoTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartFrigoTopics.clientId)
        .startClean();
    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker MQTT injoignable');
    }
    _client = client;
    client.subscribe(SmartFrigoTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartFrigoTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartFrigoTopics.alert, MqttQos.atLeastOnce);
    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );
      if (event.topic == SmartFrigoTopics.telemetry) {
        final t = FrigoTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (event.topic == SmartFrigoTopics.status) {
        final s = FrigoStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (event.topic == SmartFrigoTopics.alert) {
        final a = FrigoAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) throw StateError('Non connecte MQTT');
    final builder = MqttClientPayloadBuilder()..addString(command.trim().toUpperCase());
    client.publishMessage(SmartFrigoTopics.command, MqttQos.atLeastOnce, builder.payload!);
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
