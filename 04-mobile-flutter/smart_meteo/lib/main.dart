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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0284C7),
          brightness: Brightness.light,
        ),
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
  String? _brokerLabel;

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
    setState(() {
      _busy = true;
      _error = null;
    });

    final host = _brokerCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 1883;
    if (host.isEmpty) {
      setState(() {
        _error = 'Indiquez l\'IP du PC Mosquitto';
        _busy = false;
      });
      return;
    }

    try {
      await _mqtt.connect(host: host, port: port);
      _brokerLabel = '$host:$port';

      await _telSub?.cancel();
      _telSub = _mqtt.telemetryStream.listen((t) {
        if (mounted) setState(() => _telemetry = t);
      });

      await _statusSub?.cancel();
      _statusSub = _mqtt.statusStream.listen((s) {
        if (mounted) setState(() => _status = s);
      });

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
    if (mounted) {
      setState(() {
        _brokerLabel = null;
        _telemetry = null;
        _status = null;
      });
    }
  }

  Future<void> _cmd(String c) async {
    if (!_connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous au broker MQTT')),
      );
      return;
    }
    try {
      await _mqtt.sendCommand(c);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commande envoyée : $c')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Color _uvColor(int? uv) {
    if (uv == null) return Colors.grey;
    if (uv >= 8) return const Color(0xFFB91C1C);
    if (uv >= 6) return const Color(0xFFD97706);
    if (uv >= 3) return const Color(0xFFF59E0B);
    return const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    final t = _telemetry;

    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — Smart Meteo'),
        centerTitle: true,
        backgroundColor: const Color(0xFF0369A1),
        foregroundColor: Colors.white,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            IconButton(
              tooltip: _connected ? 'Déconnecter' : 'Connecter',
              onPressed: _connected ? _disconnect : _connect,
              icon: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              color: const Color(0xFFFEF2F2),
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                title: Text(_error!, style: const TextStyle(fontSize: 13)),
              ),
            ),
          if (!_connected) _brokerCard(),
          _connectionCard(),
          const SizedBox(height: 12),
          _metricCard(
            title: 'Température',
            icon: Icons.thermostat,
            value: t != null ? '${t.temp.toStringAsFixed(1)} °C' : '—',
            subtitle: t != null ? 'HR ${t.hum.toStringAsFixed(0)} %' : null,
            color: const Color(0xFFEA580C),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Pression',
                  icon: Icons.speed,
                  value: t != null ? '${t.pressure.toStringAsFixed(1)} hPa' : '—',
                  color: const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  title: 'Vent',
                  icon: Icons.air,
                  value: t != null ? '${t.windKmh.toStringAsFixed(1)} km/h' : '—',
                  color: const Color(0xFF0EA5E9),
                  child: t != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: (t.windKmh / 60).clamp(0.0, 1.0),
                            minHeight: 8,
                            backgroundColor: const Color(0xFFE5E7EB),
                            color: t.windKmh > 35 ? const Color(0xFFD97706) : const Color(0xFF0EA5E9),
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Pluie cumulée',
                  icon: Icons.grain,
                  value: t != null ? '${t.rainMm.toStringAsFixed(2)} mm' : '—',
                  color: const Color(0xFF2563EB),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  title: 'Indice UV',
                  icon: Icons.wb_sunny_outlined,
                  value: t != null ? '${t.uvIndex}' : '—',
                  color: _uvColor(t?.uvIndex),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _controlsCard(),
          const SizedBox(height: 12),
          _alertsCard(),
          const SizedBox(height: 16),
          Text(
            'Flashez 10-smart-meteo/esp32-smart-meteo et lancez Mosquitto (05-iot-mqtt).',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _brokerCard() {
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
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.cloud_queue),
                label: const Text('Connecter à la station'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0369A1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionCard() {
    final station = _telemetry?.station ?? _status?.station ?? '—';
    final mode = _status?.mode ?? '—';
    return Card(
      color: _connected ? const Color(0xFFEFF6FF) : null,
      child: ListTile(
        leading: Icon(
          _connected ? Icons.cloud : Icons.portable_wifi_off,
          color: _connected ? const Color(0xFF0284C7) : Colors.grey,
        ),
        title: Text(_connected ? 'MQTT : $_brokerLabel' : 'Non connecté'),
        subtitle: Text(
          _telemetry != null
              ? 'Station $station · Mode $mode · Vent ${_telemetry!.windKmh.toStringAsFixed(0)} km/h'
              : 'En attente de télémétrie eljezi/meteo/telemetry…',
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required IconData icon,
    required String value,
    String? subtitle,
    required Color color,
    Widget? child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ],
            if (child != null) ...[const SizedBox(height: 10), child],
          ],
        ),
      ),
    );
  }

  Widget _controlsCard() {
    final mode = _status?.mode ?? '—';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Station · Mode $mode', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _connected ? () => _cmd('STATUS') : _connect,
                    icon: Icon(_connected ? Icons.refresh : Icons.cloud_queue),
                    label: Text(_connected ? 'Rafraîchir' : 'Connecter'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0369A1)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _connected ? () => _cmd('RESET_RAIN') : null,
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Reset pluie'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _connected ? () => _cmd('MODE_AUTO') : null,
                    child: const Text('Mode AUTO'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _connected ? () => _cmd('MODE_MANUAL') : null,
                    child: const Text('Mode MANUEL'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Alertes météo', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_alerts.isEmpty)
              Text('Aucune alerte', style: TextStyle(color: Colors.grey.shade600, fontSize: 13))
            else
              ..._alerts.take(8).map(
                    (a) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.warning_amber, color: Color(0xFFD97706), size: 20),
                      title: Text(a.alert, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(a.station, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
