import 'dart:async';

import 'package:flutter/material.dart';

import 'mqtt/smart_meteo_mqtt_client.dart';

void main() => runApp(const SmartMeteoApp());

class SmartMeteoApp extends StatelessWidget {
  const SmartMeteoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Meteo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0284C7), brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const MeteoPage(),
    );
  }
}

class MeteoPage extends StatefulWidget {
  const MeteoPage({super.key});

  @override
  State<MeteoPage> createState() => _MeteoPageState();
}

class _MeteoPageState extends State<MeteoPage> {
  final _mqtt = SmartMeteoMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');

  MeteoTelemetry? _telemetry;
  MeteoStatus? _status;
  final List<MeteoAlert> _alerts = [];
  String? _error;
  bool _busy = false;

  StreamSubscription<MeteoTelemetry>? _telSub;
  StreamSubscription<MeteoStatus>? _statusSub;
  StreamSubscription<MeteoAlert>? _alertSub;

  bool get _connected => _mqtt.isConnected;

  @override
  void dispose() {
    _telSub?.cancel();
    _statusSub?.cancel();
    _alertSub?.cancel();
    _mqtt.dispose();
    _brokerCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() { _busy = true; _error = null; });
    final host = _brokerCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 1883;
    if (host.isEmpty) {
      setState(() { _error = 'Indiquez l\'IP du broker'; _busy = false; });
      return;
    }
    try {
      await _mqtt.connect(host: host, port: port);
      await _telSub?.cancel();
      _telSub = _mqtt.telemetryStream.listen((t) { if (mounted) setState(() => _telemetry = t); });
      await _statusSub?.cancel();
      _statusSub = _mqtt.statusStream.listen((s) { if (mounted) setState(() => _status = s); });
      await _alertSub?.cancel();
      _alertSub = _mqtt.alertStream.listen((a) {
        if (mounted) {
          setState(() {
            _alerts.insert(0, a);
            if (_alerts.length > 15) _alerts.removeLast();
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

  Future<void> _disconnect() async {
    await _telSub?.cancel();
    await _statusSub?.cancel();
    await _alertSub?.cancel();
    await _mqtt.disconnect();
    if (mounted) setState(() { _telemetry = null; _status = null; });
  }

  Future<void> _cmd(String c) async {
    if (!_connected) return;
    try {
      await _mqtt.sendCommand(c);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _telemetry;
    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — Smart Meteo'),
        backgroundColor: const Color(0xFF0369A1),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _busy ? null : (_connected ? _disconnect : _connect),
            icon: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(color: const Color(0xFFFEF2F2), child: ListTile(title: Text(_error!, style: const TextStyle(fontSize: 13)))),
          if (!_connected) ...[
            TextField(controller: _brokerCtrl, decoration: const InputDecoration(labelText: 'IP broker', border: OutlineInputBorder())),
            const SizedBox(height: 8),
            TextField(controller: _portCtrl, decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()), keyboardType: TextInputType.number),
            const SizedBox(height: 12),
          ],
          _card('Temperature', '${t?.temp.toStringAsFixed(1) ?? "—"} °C', Icons.thermostat, const Color(0xFFEA580C)),
          _card('Humidite', '${t?.hum.toStringAsFixed(0) ?? "—"} %', Icons.water_drop_outlined, const Color(0xFF0284C7)),
          Row(children: [
            Expanded(child: _card('Pression', '${t?.pressure.toStringAsFixed(1) ?? "—"} hPa', Icons.speed, const Color(0xFF6366F1))),
            const SizedBox(width: 8),
            Expanded(child: _card('Vent', '${t?.windKmh.toStringAsFixed(1) ?? "—"} km/h', Icons.air, const Color(0xFF0EA5E9))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _card('Pluie', '${t?.rainMm.toStringAsFixed(2) ?? "—"} mm', Icons.grain, const Color(0xFF2563EB))),
            const SizedBox(width: 8),
            Expanded(child: _card('UV', '${t?.uvIndex ?? "—"}', Icons.wb_sunny_outlined, const Color(0xFFF59E0B))),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Station ${t?.station ?? _status?.station ?? "—"} · Mode ${_status?.mode ?? "—"}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(onPressed: _connected ? () => _cmd('STATUS') : null, child: const Text('Rafraichir')),
                  OutlinedButton(onPressed: _connected ? () => _cmd('RESET_RAIN') : null, child: const Text('Reset pluie')),
                  OutlinedButton(onPressed: _connected ? () => _cmd('MODE_AUTO') : null, child: const Text('AUTO')),
                  OutlinedButton(onPressed: _connected ? () => _cmd('MODE_MANUAL') : null, child: const Text('MANUEL')),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Alertes meteo', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_alerts.isEmpty)
                  Text('Aucune alerte', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
                else
                  ..._alerts.take(8).map((a) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.warning_amber, color: Color(0xFFD97706)),
                        title: Text(a.alert, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(a.station),
                      )),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
        ]),
      ),
    );
  }
}
