import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

abstract final class SmartPoubelleTopics {
  static const telemetry = 'eljezi/poubelle/telemetry';
  static const command = 'eljezi/poubelle/command';
  static const status = 'eljezi/poubelle/status';
  static const alert = 'eljezi/poubelle/alert';
  static const clientId = 'ElJezi-Flutter-SmartPoubelle';
}

class PoubelleTelemetry {
  const PoubelleTelemetry({
    required this.binId,
    required this.wasteType,
    required this.fillPct,
    required this.weightKg,
    required this.lidOpen,
    required this.gasPpm,
    required this.batteryPct,
    required this.tempC,
    required this.humidity,
  });

  final String binId;
  final String wasteType;
  final int fillPct;
  final double weightKg;
  final bool lidOpen;
  final int gasPpm;
  final int batteryPct;
  final double tempC;
  final double humidity;

  static PoubelleTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'BIN\s*=\s*([^,]+)\s*,\s*'
      r'TYPE\s*=\s*([^,]+)\s*,\s*'
      r'FILL\s*=\s*(\d+)\s*,\s*'
      r'WEIGHT\s*=\s*([-.\d]+)\s*,\s*'
      r'LID\s*=\s*(\d)\s*,\s*'
      r'GAS\s*=\s*(\d+)\s*,\s*'
      r'BATT\s*=\s*(\d+)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return PoubelleTelemetry(
      binId: m.group(1)!.trim(),
      wasteType: m.group(2)!.trim().toUpperCase(),
      fillPct: int.tryParse(m.group(3)!) ?? 0,
      weightKg: double.tryParse(m.group(4)!) ?? 0,
      lidOpen: m.group(5) == '1',
      gasPpm: int.tryParse(m.group(6)!) ?? 0,
      batteryPct: int.tryParse(m.group(7)!) ?? 100,
      tempC: double.tryParse(m.group(8)!) ?? 0,
      humidity: double.tryParse(m.group(9)!) ?? 0,
    );
  }
}

class PoubelleStatus {
  const PoubelleStatus({
    required this.binId,
    required this.online,
    required this.mode,
    required this.collectionDue,
    required this.alarmOn,
  });

  final String binId;
  final bool online;
  final String mode;
  final bool collectionDue;
  final bool alarmOn;

  static PoubelleStatus? tryParse(String raw) {
    final m = RegExp(
      r'BIN\s*=\s*([^,]+)\s*,\s*'
      r'ONLINE\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(\w+)\s*,\s*'
      r'COLLECT\s*=\s*(\d)\s*,\s*'
      r'ALARM\s*=\s*(\d)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return PoubelleStatus(
      binId: m.group(1)!.trim(),
      online: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
      collectionDue: m.group(4) == '1',
      alarmOn: m.group(5) == '1',
    );
  }
}

class PoubelleAlert {
  const PoubelleAlert({required this.binId, required this.alert});

  final String binId;
  final String alert;

  static PoubelleAlert? tryParse(String raw) {
    final m = RegExp(
      r'BIN\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*([\w_,.=]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return PoubelleAlert(binId: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

class SmartPoubelleMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<PoubelleTelemetry>.broadcast();
  final _statusCtrl = StreamController<PoubelleStatus>.broadcast();
  final _alertCtrl = StreamController<PoubelleAlert>.broadcast();

  Stream<PoubelleTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<PoubelleStatus> get statusStream => _statusCtrl.stream;
  Stream<PoubelleAlert> get alertStream => _alertCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();

    final client = MqttServerClient.withPort(host, SmartPoubelleTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartPoubelleTopics.clientId)
        .startClean();

    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker MQTT injoignable');
    }

    _client = client;
    client.subscribe(SmartPoubelleTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartPoubelleTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartPoubelleTopics.alert, MqttQos.atLeastOnce);
    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );
      if (topic == SmartPoubelleTopics.telemetry) {
        final t = PoubelleTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (topic == SmartPoubelleTopics.status) {
        final s = PoubelleStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (topic == SmartPoubelleTopics.alert) {
        final a = PoubelleAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) throw StateError('Non connecte MQTT');
    final builder = MqttClientPayloadBuilder()..addString(command.trim().toUpperCase());
    client.publishMessage(SmartPoubelleTopics.command, MqttQos.atLeastOnce, builder.payload!);
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
