import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

abstract final class SmartMeteoTopics {
  static const telemetry = 'eljezi/meteo/telemetry';
  static const command = 'eljezi/meteo/command';
  static const status = 'eljezi/meteo/status';
  static const alert = 'eljezi/meteo/alert';
  static const clientId = 'ElJezi-Flutter-SmartMeteo';
}

class MeteoTelemetry {
  const MeteoTelemetry({
    required this.station,
    required this.temp,
    required this.hum,
    required this.pressure,
    required this.windKmh,
    required this.rainMm,
    required this.uvIndex,
  });

  final String station;
  final double temp;
  final double hum;
  final double pressure;
  final double windKmh;
  final double rainMm;
  final int uvIndex;

  static MeteoTelemetry? tryParse(String raw) {
    final m = RegExp(
      r'STATION\s*=\s*([^,]+)\s*,\s*'
      r'T\s*=\s*([-.\d]+)\s*,\s*'
      r'H\s*=\s*([-.\d]+)\s*,\s*'
      r'P\s*=\s*([-.\d]+)\s*,\s*'
      r'W\s*=\s*([-.\d]+)\s*,\s*'
      r'R\s*=\s*([-.\d]+)\s*,\s*'
      r'UV\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return MeteoTelemetry(
      station: m.group(1)!.trim(),
      temp: double.tryParse(m.group(2)!) ?? 0,
      hum: double.tryParse(m.group(3)!) ?? 0,
      pressure: double.tryParse(m.group(4)!) ?? 0,
      windKmh: double.tryParse(m.group(5)!) ?? 0,
      rainMm: double.tryParse(m.group(6)!) ?? 0,
      uvIndex: int.tryParse(m.group(7)!) ?? 0,
    );
  }
}

class MeteoStatus {
  const MeteoStatus({required this.station, required this.online, required this.mode});

  final String station;
  final bool online;
  final String mode;

  static MeteoStatus? tryParse(String raw) {
    final m = RegExp(
      r'STATION\s*=\s*([^,]+)\s*,\s*ONLINE\s*=\s*(\d)\s*,\s*MODE\s*=\s*(AUTO|MANUAL)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return MeteoStatus(
      station: m.group(1)!.trim(),
      online: m.group(2) == '1',
      mode: m.group(3)!.toUpperCase(),
    );
  }
}

class MeteoAlert {
  const MeteoAlert({required this.station, required this.alert});

  final String station;
  final String alert;

  static MeteoAlert? tryParse(String raw) {
    final m = RegExp(
      r'STATION\s*=\s*([^,]+)\s*,\s*ALERT\s*=\s*([\w_,.=]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return MeteoAlert(station: m.group(1)!.trim(), alert: m.group(2)!);
  }
}

class SmartMeteoMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<MeteoTelemetry>.broadcast();
  final _statusCtrl = StreamController<MeteoStatus>.broadcast();
  final _alertCtrl = StreamController<MeteoAlert>.broadcast();

  Stream<MeteoTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<MeteoStatus> get statusStream => _statusCtrl.stream;
  Stream<MeteoAlert> get alertStream => _alertCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();

    final client = MqttServerClient.withPort(host, SmartMeteoTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(SmartMeteoTopics.clientId)
        .startClean();

    await client.connect();
    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      client.disconnect();
      throw StateError('Broker MQTT injoignable');
    }

    _client = client;
    client.subscribe(SmartMeteoTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(SmartMeteoTopics.status, MqttQos.atLeastOnce);
    client.subscribe(SmartMeteoTopics.alert, MqttQos.atLeastOnce);
    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );
      if (topic == SmartMeteoTopics.telemetry) {
        final t = MeteoTelemetry.tryParse(payload);
        if (t != null) _telemetryCtrl.add(t);
      } else if (topic == SmartMeteoTopics.status) {
        final s = MeteoStatus.tryParse(payload);
        if (s != null) _statusCtrl.add(s);
      } else if (topic == SmartMeteoTopics.alert) {
        final a = MeteoAlert.tryParse(payload);
        if (a != null) _alertCtrl.add(a);
      }
    }
  }

  Future<void> sendCommand(String command) async {
    final client = _client;
    if (client == null || !isConnected) throw StateError('Non connecte MQTT');
    final builder = MqttClientPayloadBuilder()..addString(command.trim().toUpperCase());
    client.publishMessage(SmartMeteoTopics.command, MqttQos.atLeastOnce, builder.payload!);
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
