import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/eljezi_ble_client.dart';

void main() => runApp(const IotRemoteApp());

class IotRemoteApp extends StatelessWidget {
  const IotRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF059669)),
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
  final _ble = ElJeziBleClient();
  StreamSubscription<SensorSample>? _statusSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  bool _ledOn = false;
  bool _relayOn = false;
  int _pwm = 128;
  String _lastCmd = '—';
  String? _error;
  bool _busy = false;
  SensorSample? _sample;
  String? _deviceLabel;

  bool get _connected => _ble.isConnected;

  @override
  void dispose() {
    _statusSub?.cancel();
    _connSub?.cancel();
    _ble.disconnect();
    super.dispose();
  }

  Future<void> _connectBle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await _ble.scanForEsp32();
      if (device == null) {
        setState(() => _error = 'ESP32 « ${ElJeziBleUuids.deviceName} » introuvable. Vérifiez le flash firmware.');
        return;
      }
      await _ble.connect(device);
      _deviceLabel = device.platformName.isNotEmpty ? device.platformName : ElJeziBleUuids.deviceName;

      await _statusSub?.cancel();
      _statusSub = _ble.statusStream().listen((s) {
        if (mounted) setState(() => _sample = s);
      });

      await _connSub?.cancel();
      _connSub = _ble.connectionState().listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(() {
            _deviceLabel = null;
            _sample = null;
          });
        }
      });

      await _ble.sendCommand('STATUS');
      final initial = await _ble.readStatusOnce();
      if (mounted && initial != null) _sample = initial;
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnectBle() async {
    await _statusSub?.cancel();
    await _connSub?.cancel();
    _statusSub = null;
    _connSub = null;
    await _ble.disconnect();
    if (mounted) {
      setState(() {
        _deviceLabel = null;
        _sample = null;
      });
    }
  }

  Future<void> _sendCommand(String cmd) async {
    setState(() => _lastCmd = cmd);
    if (!_connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous à l\'ESP32 via BLE')),
      );
      return;
    }
    try {
      await _ble.sendCommand(cmd);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — IoT Remote'),
        centerTitle: true,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              tooltip: _connected ? 'Déconnecter BLE' : 'Connecter ESP32',
              onPressed: _connected ? _disconnectBle : _connectBle,
              icon: Icon(_connected ? Icons.bluetooth_connected : Icons.bluetooth_searching),
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
          _statusCard(),
          const SizedBox(height: 16),
          _switchTile(
            title: 'LED embarquée',
            subtitle: 'GPIO 2 — commande BLE LED_ON / LED_OFF',
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
            onPressed: _connected ? () => _sendCommand('STATUS') : _connectBle,
            icon: Icon(_connected ? Icons.refresh : Icons.bluetooth),
            label: Text(_connected ? 'Rafraîchir capteurs' : 'Scanner & connecter ESP32'),
          ),
          const SizedBox(height: 16),
          const Text('Firmware', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            'Flashez 01-rtos/esp32-freertos-blinky puis connectez-vous à « ${ElJeziBleUuids.deviceName} ».',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final s = _sample;
    return Card(
      color: _connected ? const Color(0xFFECFDF5) : null,
      child: ListTile(
        leading: Icon(
          _connected ? Icons.link : Icons.link_off,
          color: _connected ? const Color(0xFF059669) : Colors.grey,
        ),
        title: Text(_connected ? 'BLE : $_deviceLabel' : 'Non connecté'),
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
