import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

abstract final class SmartStationTopics {
  static const telemetry = 'eljezi/station/telemetry';
  static const command = 'eljezi/station/command';
  static const status = 'eljezi/station/status';
  static const alert = 'eljezi/station/alert';
  static const clientId = 'ElJezi-Flutter-SmartStation';
}

class StationTelemetry {
  const StationTelemetry({
    required this.stationId,
    required this.lineId,
    required this.vehicleType,
    required this.direction,
    required this.etaMin,
    required this.occupancyPct,
    required this.validators,
    required this.tempC,
    required this.humidity,
    required this.crowdLevel,
  });

  final String stationId;
  final String lineId;
  final String vehicleType;
  final String direction;
  final int etaMin;
  final int occupancyPct;
  final int validators;
  final double tempC;
  final double humidity;
  final int crowdLevel;

  static StationTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'STATION\s*=\s*([^,]+)\s*,\s*'
      r'LINE\s*=\s*([^,]+)\s*,\s*'
      r'VEHICLE\s*=\s*([^,]+)\s*,\s*'
      r'DIR\s*=\s*([^,]+)\s*,\s*'
      r'ETA\s*=\s*(\d+)\s*,\s*'
      r'OCC\s*=\s*(\d+)\s*,\s*'
      r'VALIDATORS\s*=\s*(\d+)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)\s*,\s*'
      r'CROWD\s*=\s*(\d)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return StationTelemetry(
      stationId: m.group(1)!.trim(),
      lineId: m.group(2)!.trim(),
      vehicleType: m.group(3)!.trim().toUpperCase(),
      direction: m.group(4)!.trim(),
      etaMin: int.tryParse(m.group(5)!) ?? 0,
      occupancyPct: int.tryParse(m.group(6)!) ?? 0,
      validators: int.tryParse(m.group(7)!) ?? 0,
      tempC: double.tryParse(m.group(8)!) ?? 0,
      humidity: double.tryParse(m.group(9)!) ?? 0,
      crowdLevel: int.tryParse(m.group(10)!) ?? 1,
    );
  }
}

class StationStatus {
  const StationStatus({
    required this.stationId,
    required this.online,
    required this.mode,
    required this.linesCount,
    required this.servicesUp,
  });

  final String stationId;
  final bool online;
  final String mode;
  final int linesCount;
  final int servicesUp;

  static StationStatus? tryParse(String raw) {
    final m = RegExp(
      r'STATION\s*=\s*([^,]+)\s*,\s*'
      r'ONLINE\s*=\s*(\d)\s*,\s*'
      r'MODE\s*=\s*(NORMAL|EVENT|ALERT)\s*,\s*'
      r'LINES\s*=\s*(\d+)\s*,\s*'
      r'SERVICES\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return StationStatus(
      stationId: m.group(1)!.trim(),
      online: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
      linesCount: int.tryParse(m.group(4)!) ?? 0,
      servicesUp: int.tryParse(m.group(5)!) ?? 0,
    );
  }
}

class StationAlert {
  const StationAlert({required this.stationId, required this.alert});

  final String stationId;
  final String alert;

  static StationAlert? tryParse(String raw) {
    final m = RegExp(
      r'STATION\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*([\w_,.=]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return StationAlert(stationId: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

class SmartStationMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<StationTelemetry>.broadcast();
  final _statusCtrl = StreamController<StationStatus>.broadcast();
  final _alertCtrl = StreamController<StationAlert>.broadcast();

  Stream<StationTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<StationStatus> get statusStream => _statusCtrl.stream;
  Stream<StationAlert> get alertStream => _alertCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();

    final client = MqttServerClient.withPort(host, SmartStationTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartStationTopics.clientId)
        .startClean();

    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker MQTT injoignable');
    }

    _client = client;
    client.subscribe(SmartStationTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartStationTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartStationTopics.alert, MqttQos.atLeastOnce);
    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );
      if (topic == SmartStationTopics.telemetry) {
        final t = StationTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (topic == SmartStationTopics.status) {
        final s = StationStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (topic == SmartStationTopics.alert) {
        final a = StationAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) throw StateError('Non connecte MQTT');
    final builder = MqttClientPayloadBuilder()..addString(command.trim().toUpperCase());
    client.publishMessage(SmartStationTopics.command, MqttQos.atLeastOnce, builder.payload!);
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
