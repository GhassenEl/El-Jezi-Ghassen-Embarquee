import 'dart:async';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Protocole MQTT partagé ESP32 ↔ Flutter (voir aussi 05-iot-mqtt).
abstract final class ElJeziMqttTopics {
  static const telemetry = 'eljezi/esp32/telemetry';
  static const command = 'eljezi/esp32/command';
  static const status = 'eljezi/esp32/status';
  static const clientId = 'ElJezi-Flutter-MQTT';
}

class SensorSample {
  const SensorSample({required this.temp, required this.humidity, required this.voltage});

  final double temp;
  final double humidity;
  final double voltage;

  static SensorSample? tryParse(String raw) {
    final m = RegExp(
      r'T\s*=\s*([-.\d]+)\s*,\s*H\s*=\s*([-.\d]+)\s*,\s*V\s*=\s*([-.\d]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return SensorSample(
      temp: double.tryParse(m.group(1)!) ?? 0,
      humidity: double.tryParse(m.group(2)!) ?? 0,
      voltage: double.tryParse(m.group(3)!) ?? 0,
    );
  }
}

class DeviceStatus {
  const DeviceStatus({required this.ledOn, required this.relayOn, required this.pwm});

  final bool ledOn;
  final bool relayOn;
  final int pwm;

  static DeviceStatus? tryParse(String raw) {
    final m = RegExp(
      r'LED\s*=\s*(\d+)\s*,\s*RELAY\s*=\s*(\d+)\s*,\s*PWM\s*=\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return DeviceStatus(
      ledOn: m.group(1) == '1',
      relayOn: m.group(2) == '1',
      pwm: int.tryParse(m.group(3)!) ?? 0,
    );
  }
}

/// Client MQTT pour broker Mosquitto + ESP32 El Jezi.
class ElJeziMqttClient {
  MqttServerClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updatesSub;

  final _telemetryCtrl = StreamController<SensorSample>.broadcast();
  final _statusCtrl = StreamController<DeviceStatus>.broadcast();
  final _connectionCtrl = StreamController<bool>.broadcast();

  Stream<SensorSample> get telemetryStream => _telemetryCtrl.stream;
  Stream<DeviceStatus> get statusStream => _statusCtrl.stream;
  Stream<bool> get connectionStream => _connectionCtrl.stream;

  bool get isConnected => _client?.connectionStatus?.state == MqttConnectionState.connected;

  String? get brokerHost => _client?.server;

  Future<void> connect({required String host, int port = 1883}) async {
    await disconnect();

    final client = MqttServerClient.withPort(host, ElJeziMqttTopics.clientId, port);
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.autoReconnect = true;
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(ElJeziMqttTopics.clientId)
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

    client.subscribe(ElJeziMqttTopics.telemetry, MqttQos.atLeastOnce);
    client.subscribe(ElJeziMqttTopics.status, MqttQos.atLeastOnce);

    _updatesSub = client.updates?.listen(_onMessage);
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      final topic = event.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (event.payload as MqttPublishMessage).payload.message,
      );

      if (topic == ElJeziMqttTopics.telemetry) {
        final sample = SensorSample.tryParse(payload);
        if (sample != null) _telemetryCtrl.add(sample);
      } else if (topic == ElJeziMqttTopics.status) {
        final status = DeviceStatus.tryParse(payload);
        if (status != null) _statusCtrl.add(status);
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
      ElJeziMqttTopics.command,
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
    _connectionCtrl.close();
  }
}
