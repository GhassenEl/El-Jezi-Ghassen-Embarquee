import 'dart:async';

import 'package:flutter/material.dart';

import 'mqtt/smart_frigo_mqtt_client.dart';

void main() => runApp(const SmartFrigoApp());

class SmartFrigoApp extends StatelessWidget {
  const SmartFrigoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Frigo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0891B2), brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const FrigoPage(),
    );
  }
}

class FrigoPage extends StatefulWidget {
  const FrigoPage({super.key});

  @override
  State<FrigoPage> createState() => _FrigoPageState();
}

class _FrigoPageState extends State<FrigoPage> {
  final _mqtt = SmartFrigoMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');

  FrigoTelemetry? _telemetry;
  FrigoStatus? _status;
  final List<FrigoAlert> _alerts = [];
  String? _error;
  bool _busy = false;
  String? _brokerLabel;

  StreamSubscription<FrigoTelemetry>? _telSub;
  StreamSubscription<FrigoStatus>? _statusSub;
  StreamSubscription<FrigoAlert>? _alertSub;

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
      setState(() { _error = 'Indiquez l\'IP du PC Mosquitto'; _busy = false; });
      return;
    }
    try {
      await _mqtt.connect(host: host, port: port);
      _brokerLabel = '$host:$port';
      await _telSub?.cancel();
      _telSub = _mqtt.telemetryStream.listen((t) { if (mounted) setState(() => _telemetry = t); });
      await _statusSub?.cancel();
      _statusSub = _mqtt.statusStream.listen((s) { if (mounted) setState(() => _status = s); });
      await _alertSub?.cancel();
      _alertSub = _mqtt.alertStream.listen((a) {
        if (mounted) {
          setState(() {
            _alerts.insert(0, a);
            if (_alerts.length > 20) _alerts.removeLast();
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
    if (mounted) setState(() { _brokerLabel = null; _telemetry = null; _status = null; });
  }

  Future<void> _cmd(String c) async {
    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connectez-vous au broker MQTT')));
      return;
    }
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
        title: const Text('El Jezi — Smart Frigo'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0E7490),
        foregroundColor: Colors.white,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            )
          else
            IconButton(
              onPressed: _connected ? _disconnect : _connect,
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
            FilledButton.icon(
              onPressed: _busy ? null : _connect,
              icon: const Icon(Icons.kitchen),
              label: const Text('Connecter au frigo'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0E7490)),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            color: _connected ? const Color(0xFFECFEFF) : null,
            child: ListTile(
              leading: Icon(_connected ? Icons.kitchen : Icons.portable_wifi_off, color: _connected ? const Color(0xFF0891B2) : Colors.grey),
              title: Text(_connected ? 'MQTT : $_brokerLabel' : 'Non connecte'),
              subtitle: Text(t != null
                  ? 'Zone ${t.zone} · Porte ${t.doorOpen ? "OUVERTE" : "fermee"} · ${t.powerW} W'
                  : 'En attente eljezi/frigo/telemetry…'),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _metric('Frigo', t != null ? '${t.fridgeTemp.toStringAsFixed(1)} °C' : '—', Icons.ac_unit, const Color(0xFF06B6D4))),
            const SizedBox(width: 8),
            Expanded(child: _metric('Congelateur', t != null ? '${t.freezerTemp.toStringAsFixed(1)} °C' : '—', Icons.severe_cold, const Color(0xFF0284C7))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _metric('Compresseur', t != null ? (t.compressorOn ? 'ON' : 'OFF') : '—', Icons.settings, const Color(0xFF6366F1))),
            const SizedBox(width: 8),
            Expanded(child: _metric('Humidite', t != null ? '${t.humidity.toStringAsFixed(0)} %' : '—', Icons.water_drop_outlined, const Color(0xFF0EA5E9))),
          ]),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Mode ${_status?.mode ?? "—"} · Cibles ${_status?.targetFridge ?? "—"}°C / ${_status?.targetFreezer ?? "—"}°C',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton(onPressed: _connected ? () => _cmd('STATUS') : _connect, child: Text(_connected ? 'Rafraichir' : 'Connecter')),
                  OutlinedButton(onPressed: _connected ? () => _cmd('MODE_ECO') : null, child: const Text('ECO')),
                  OutlinedButton(onPressed: _connected ? () => _cmd('MODE_NORMAL') : null, child: const Text('NORMAL')),
                  OutlinedButton(onPressed: _connected ? () => _cmd('ALARM_OFF') : null, child: const Text('Couper alarme')),
                ]),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Alertes frigo', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (_alerts.isEmpty)
                  Text('Aucune alerte', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
                else
                  ..._alerts.take(8).map((a) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.warning_amber, color: t?.doorOpen == true ? const Color(0xFFD97706) : const Color(0xFFF59E0B), size: 20),
                        title: Text(a.alert, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(a.zone),
                      )),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}
