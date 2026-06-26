import 'dart:async';

import 'package:flutter/material.dart';

import 'mqtt/eljezi_mqtt_client.dart';

void main() => runApp(const MqttRemoteApp());

class MqttRemoteApp extends StatelessWidget {
  const MqttRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MQTT Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const RemotePage(),
    );
  }
}

class RemotePage extends StatefulWidget {
  const RemotePage({super.key});

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  final _mqtt = ElJeziMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');

  StreamSubscription<SensorSample>? _telemetrySub;
  StreamSubscription<DeviceStatus>? _statusSub;

  bool _ledOn = false;
  bool _relayOn = false;
  int _pwm = 128;
  String _lastCmd = '—';
  String? _error;
  bool _busy = false;
  SensorSample? _sample;
  String? _brokerLabel;

  bool get _connected => _mqtt.isConnected;

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _statusSub?.cancel();
    _mqtt.dispose();
    _brokerCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _connectMqtt() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final host = _brokerCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 1883;

    if (host.isEmpty) {
      setState(() {
        _error = 'Indiquez l\'IP du PC qui héberge Mosquitto';
        _busy = false;
      });
      return;
    }

    try {
      await _mqtt.connect(host: host, port: port);
      _brokerLabel = '$host:$port';

      await _telemetrySub?.cancel();
      _telemetrySub = _mqtt.telemetryStream.listen((s) {
        if (mounted) setState(() => _sample = s);
      });

      await _statusSub?.cancel();
      _statusSub = _mqtt.statusStream.listen((s) {
        if (mounted) {
          setState(() {
            _ledOn = s.ledOn;
            _relayOn = s.relayOn;
            _pwm = s.pwm;
          });
        }
      });

      await _mqtt.sendCommand('STATUS');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectMqtt() async {
    await _telemetrySub?.cancel();
    await _statusSub?.cancel();
    _telemetrySub = null;
    _statusSub = null;
    await _mqtt.disconnect();
    if (mounted) {
      setState(() {
        _brokerLabel = null;
        _sample = null;
      });
    }
  }

  Future<void> _sendCommand(String cmd) async {
    setState(() => _lastCmd = cmd);
    if (!_connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous au broker MQTT')),
      );
      return;
    }
    try {
      await _mqtt.sendCommand(cmd);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — MQTT Remote'),
        centerTitle: true,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              tooltip: _connected ? 'Déconnecter MQTT' : 'Connecter broker',
              onPressed: _connected ? _disconnectMqtt : _connectMqtt,
              icon: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            Card(
              color: const Color(0xFFFEF2F2),
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                title: Text(_error!, style: const TextStyle(fontSize: 13)),
              ),
            ),
          if (!_connected) _brokerConfigCard(),
          _statusCard(),
          const SizedBox(height: 16),
          _switchTile(
            title: 'LED embarquée',
            subtitle: 'GPIO 2 — LED_ON / LED_OFF',
            value: _ledOn,
            icon: Icons.lightbulb,
            onChanged: _connected
                ? (v) {
                    setState(() => _ledOn = v);
                    _sendCommand(v ? 'LED_ON' : 'LED_OFF');
                  }
                : null,
          ),
          _switchTile(
            title: 'Relais',
            subtitle: 'GPIO 4 — RELAY_ON / RELAY_OFF',
            value: _relayOn,
            icon: Icons.power,
            onChanged: _connected
                ? (v) {
                    setState(() => _relayOn = v);
                    _sendCommand(v ? 'RELAY_ON' : 'RELAY_OFF');
                  }
                : null,
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PWM ventilateur', style: TextStyle(fontWeight: FontWeight.w700)),
                  Slider(
                    value: _pwm.toDouble(),
                    min: 0,
                    max: 255,
                    divisions: 255,
                    label: '$_pwm',
                    onChanged: _connected ? (v) => setState(() => _pwm = v.round()) : null,
                    onChangeEnd: _connected ? (v) => _sendCommand('PWM_${v.round()}') : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _connected ? () => _sendCommand('STATUS') : _connectMqtt,
            icon: Icon(_connected ? Icons.refresh : Icons.cloud_queue),
            label: Text(_connected ? 'Rafraîchir capteurs' : 'Connecter au broker'),
          ),
          const SizedBox(height: 16),
          const Text('Configuration', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '1. Lancez Mosquitto (05-iot-mqtt/mosquitto)\n'
            '2. Flashez esp32-mqtt-sensors avec secrets.h\n'
            '3. Entrez l\'IP LAN du PC (pas localhost sur téléphone)',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _brokerConfigCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Broker Mosquitto', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _brokerCtrl,
              decoration: const InputDecoration(
                labelText: 'IP du broker',
                border: OutlineInputBorder(),
                hintText: '192.168.1.100',
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(
                labelText: 'Port',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    final s = _sample;
    return Card(
      color: _connected ? const Color(0xFFEFF6FF) : null,
      child: ListTile(
        leading: Icon(
          _connected ? Icons.wifi_tethering : Icons.portable_wifi_off,
          color: _connected ? const Color(0xFF2563EB) : Colors.grey,
        ),
        title: Text(_connected ? 'MQTT : $_brokerLabel' : 'Non connecté'),
        subtitle: Text(
          s != null
              ? 'T=${s.temp.toStringAsFixed(1)}°C  H=${s.humidity.toStringAsFixed(0)}%  V=${s.voltage.toStringAsFixed(2)}V\nCmd: $_lastCmd'
              : 'Dernière commande : $_lastCmd',
        ),
        isThreeLine: s != null,
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool>? onChanged,
  }) {
    return Card(
      child: SwitchListTile(
        secondary: Icon(icon, color: value ? const Color(0xFFF59E0B) : Colors.grey),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
