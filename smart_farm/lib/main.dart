import 'dart:async';

import 'package:flutter/material.dart';

import 'api/farm_cloud_client.dart';
import 'mqtt/smart_farm_mqtt_client.dart';

void main() => runApp(const SmartFarmApp());

class SmartFarmApp extends StatelessWidget {
  const SmartFarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Farm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF16A34A),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const FarmPage(),
    );
  }
}

class FarmPage extends StatefulWidget {
  const FarmPage({super.key});

  @override
  State<FarmPage> createState() => _FarmPageState();
}

class _FarmPageState extends State<FarmPage> {
  final _mqtt = SmartFarmMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');
  final _cloudApiCtrl = TextEditingController(text: 'http://192.168.1.100:5070');

  StreamSubscription<FarmTelemetry>? _telSub;
  StreamSubscription<FarmStatus>? _statusSub;
  StreamSubscription<FarmAlert>? _alertSub;

  FarmTelemetry? _telemetry;
  FarmStatus? _status;
  final List<FarmAlert> _alerts = [];
  String? _error;
  bool _busy = false;
  int _soilThresh = 30;
  String? _brokerLabel;
  FarmAiInsights? _aiInsights;
  String? _aiError;
  bool _aiBusy = false;

  bool get _connected => _mqtt.isConnected;

  @override
  void dispose() {
    _telSub?.cancel();
    _statusSub?.cancel();
    _alertSub?.cancel();
    _mqtt.dispose();
    _brokerCtrl.dispose();
    _portCtrl.dispose();
    _cloudApiCtrl.dispose();
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
        if (mounted) {
          setState(() {
            _status = s;
            _soilThresh = s.soilThresh;
          });
        }
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

  Future<void> _fetchAiInsights() async {
    final base = _cloudApiCtrl.text.trim();
    if (base.isEmpty) {
      setState(() => _aiError = 'Indiquez l\'URL cloud-api (ex. http://192.168.1.100:5070)');
      return;
    }
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final client = FarmCloudClient(base);
      final insights = await client.fetchInsights(soilThreshold: _soilThresh);
      if (mounted) setState(() => _aiInsights = insights);
    } catch (e) {
      if (mounted) setState(() => _aiError = e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _aiAutoIrrigate() async {
    final base = _cloudApiCtrl.text.trim();
    if (base.isEmpty) return;
    setState(() => _aiBusy = true);
    try {
      final client = FarmCloudClient(base);
      final ok = await client.autoIrrigate(confirm: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Irrigation IA déclenchée' : 'Commande IA refusée')),
      );
      if (ok) await _fetchAiInsights();
    } catch (e) {
      if (mounted) setState(() => _aiError = e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  Future<void> _sendCommand(String cmd) async {
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

  Color _soilColor(double soil) {
    if (soil < 25) return const Color(0xFFB45309);
    if (soil < 40) return const Color(0xFFF59E0B);
    return const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    final t = _telemetry;
    final soil = t?.soilMoist ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — Smart Farm'),
        centerTitle: true,
        backgroundColor: const Color(0xFF14532D),
        foregroundColor: Colors.white,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
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
            title: 'Humidité du sol',
            icon: Icons.grass,
            value: t != null ? '${soil.toStringAsFixed(1)} %' : '—',
            subtitle: t?.zone ?? 'Parcelle',
            child: t != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: (soil / 100).clamp(0.0, 1.0),
                      minHeight: 10,
                      backgroundColor: const Color(0xFFE5E7EB),
                      color: _soilColor(soil),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  title: 'Air',
                  icon: Icons.thermostat,
                  value: t != null ? '${t.airTemp.toStringAsFixed(1)} °C' : '—',
                  subtitle: t != null ? 'HR ${t.airHum.toStringAsFixed(0)} %' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  title: 'Luminosité',
                  icon: Icons.wb_sunny_outlined,
                  value: t != null ? '${t.lightLux} lux' : '—',
                  subtitle: null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _irrigationCard(t),
          const SizedBox(height: 12),
          _aiCard(),
          const SizedBox(height: 12),
          _alertsCard(),
          const SizedBox(height: 16),
          Text(
            'Flashez 09-smart-farm/esp32-smart-farm et lancez Mosquitto (05-iot-mqtt).',
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
          ],
        ),
      ),
    );
  }

  Widget _connectionCard() {
    return Card(
      color: _connected ? const Color(0xFFECFDF5) : null,
      child: ListTile(
        leading: Icon(
          _connected ? Icons.agriculture : Icons.portable_wifi_off,
          color: _connected ? const Color(0xFF16A34A) : Colors.grey,
        ),
        title: Text(_connected ? 'MQTT : $_brokerLabel' : 'Non connecté'),
        subtitle: Text(
          _telemetry != null
              ? 'Zone ${_telemetry!.zone} · Pompe ${_telemetry!.pumpOn ? "ON" : "OFF"} · ${_telemetry!.mode}'
              : 'En attente de télémétrie…',
        ),
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required IconData icon,
    required String value,
    String? subtitle,
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
                Icon(icon, color: const Color(0xFF16A34A), size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
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

  Widget _irrigationCard(FarmTelemetry? t) {
    final pumpOn = t?.pumpOn ?? _status?.pumpOn ?? false;
    final isAuto = (t?.mode ?? _status?.mode ?? 'AUTO') == 'AUTO';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Irrigation', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _connected ? () => _sendCommand('PUMP_ON') : null,
                    icon: const Icon(Icons.water_drop),
                    label: const Text('Pompe ON'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _connected ? () => _sendCommand('PUMP_OFF') : null,
                    icon: const Icon(Icons.water_drop_outlined),
                    label: const Text('Pompe OFF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mode automatique'),
              subtitle: Text(pumpOn ? 'Pompe active' : 'Pompe arrêtée'),
              value: isAuto,
              onChanged: _connected
                  ? (v) => _sendCommand(v ? 'MODE_AUTO' : 'MODE_MANUAL')
                  : null,
            ),
            const SizedBox(height: 4),
            Text('Seuil sol : $_soilThresh %', style: const TextStyle(fontSize: 13)),
            Slider(
              value: _soilThresh.toDouble(),
              min: 10,
              max: 80,
              divisions: 70,
              label: '$_soilThresh',
              onChanged: _connected ? (v) => setState(() => _soilThresh = v.round()) : null,
              onChangeEnd: _connected ? (v) => _sendCommand('SET_THRESH_${v.round()}') : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _connected ? () => _sendCommand('STATUS') : _connect,
                icon: Icon(_connected ? Icons.refresh : Icons.cloud_queue),
                label: Text(_connected ? 'Rafraîchir' : 'Connecter'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiCard() {
    final ai = _aiInsights;
    Color riskColor = const Color(0xFF16A34A);
    if (ai != null) {
      switch (ai.riskLevel) {
        case 'critical':
          riskColor = const Color(0xFFB91C1C);
        case 'high':
          riskColor = const Color(0xFFD97706);
        case 'medium':
          riskColor = const Color(0xFFF59E0B);
        default:
          riskColor = const Color(0xFF16A34A);
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_outlined, color: Color(0xFF7C3AED)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('IA ferme (cloud)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                if (_aiBusy)
                  const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  IconButton(
                    tooltip: 'Analyser',
                    onPressed: _fetchAiInsights,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cloudApiCtrl,
              decoration: const InputDecoration(
                labelText: 'URL cloud-api',
                border: OutlineInputBorder(),
                hintText: 'http://192.168.1.100:5070',
                isDense: true,
              ),
            ),
            if (_aiError != null) ...[
              const SizedBox(height: 8),
              Text(_aiError!, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 12)),
            ],
            if (ai != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _metricCard(
                      title: 'Santé parcelle',
                      icon: Icons.favorite_border,
                      value: '${ai.healthScore}/100',
                      subtitle: 'Zone ${ai.zone}',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _metricCard(
                      title: 'Risque',
                      icon: Icons.shield_outlined,
                      value: ai.riskLevel.toUpperCase(),
                      subtitle: 'Tendance ${ai.soilTrend}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (ai.predictedSoil6h != null)
                Text(
                  'Sol prévu +6 h : ${ai.predictedSoil6h!.toStringAsFixed(1)} %'
                  '${ai.hoursUntilDry != null ? " · sec dans ~${ai.hoursUntilDry!.toStringAsFixed(1)} h" : ""}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              if (ai.recommendations.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...ai.recommendations.take(3).map(
                      (r) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.lightbulb_outline, size: 16, color: riskColor),
                            const SizedBox(width: 6),
                            Expanded(child: Text(r, style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ),
                    ),
              ],
              if (ai.autoIrrigateRecommended) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _aiBusy ? null : _aiAutoIrrigate,
                  icon: const Icon(Icons.auto_mode),
                  label: const Text('Irrigation IA (confirmée)'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                ),
              ],
            ] else if (_aiError == null && !_aiBusy)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Lancez farm-cloud puis « Analyser » pour les recommandations IA.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
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
            const Text('Alertes ferme', style: TextStyle(fontWeight: FontWeight.w700)),
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
                      subtitle: Text(a.zone, style: const TextStyle(fontSize: 11)),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
