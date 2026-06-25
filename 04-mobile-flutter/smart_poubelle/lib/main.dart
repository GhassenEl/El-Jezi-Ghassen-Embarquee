import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/poubelle_ai_engine.dart';
import 'api/poubelle_ai_client.dart';
import 'mqtt/smart_poubelle_mqtt_client.dart';

void main() => runApp(const SmartPoubelleApp());

class SmartPoubelleApp extends StatelessWidget {
  const SmartPoubelleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Poubelle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF16A34A), brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const PoubellePage(),
    );
  }
}

class BinInfo {
  BinInfo({required this.id, required this.name, required this.type, required this.typeLabel});

  factory BinInfo.fromJson(Map<String, dynamic> j) => BinInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        typeLabel: j['type_label']?.toString() ?? '',
      );

  final String id;
  final String name;
  final String type;
  final String typeLabel;
}

class PoubellePage extends StatefulWidget {
  const PoubellePage({super.key});

  @override
  State<PoubellePage> createState() => _PoubellePageState();
}

class _PoubellePageState extends State<PoubellePage> {
  final _mqtt = SmartPoubelleMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');
  final _aiApiCtrl = TextEditingController(text: 'http://192.168.1.100:5150');

  List<BinInfo> _bins = [];
  String _selectedBin = 'parc-lac';
  final Map<String, PoubelleTelemetry> _telemetryByBin = {};
  PoubelleStatus? _status;
  final Map<String, List<FillSample>> _historyByBin = {};
  final List<PoubelleAlert> _alerts = [];

  PoubelleAiInsights? _localAi;
  PoubelleAiInsights? _cloudAi;
  String? _aiError;
  bool _aiBusy = false;
  String? _error;
  bool _busy = false;
  String? _brokerLabel;

  StreamSubscription<PoubelleTelemetry>? _telSub;
  StreamSubscription<PoubelleStatus>? _statusSub;
  StreamSubscription<PoubelleAlert>? _alertSub;

  bool get _connected => _mqtt.isConnected;

  @override
  void initState() {
    super.initState();
    _loadSeed();
  }

  Future<void> _loadSeed() async {
    final binsRaw = await rootBundle.loadString('assets/bins.json');
    final snapRaw = await rootBundle.loadString('assets/demo_snapshot.json');
    final histRaw = await rootBundle.loadString('assets/demo_history.json');
    final binsData = jsonDecode(binsRaw) as Map<String, dynamic>;
    final snap = jsonDecode(snapRaw) as Map<String, dynamic>;
    final hist = jsonDecode(histRaw) as Map<String, dynamic>;
    setState(() {
      _bins = (binsData['bins'] as List).map((e) => BinInfo.fromJson(e as Map<String, dynamic>)).toList();
      _seedFromJson(snap, hist);
      _refreshLocalAi();
    });
  }

  void _seedFromJson(Map<String, dynamic> snap, Map<String, dynamic> hist) {
    _telemetryByBin.clear();
    _historyByBin.clear();
    _alerts.clear();

    for (final b in snap['bins_live'] as List) {
      final m = b as Map<String, dynamic>;
      final binId = m['bin_id'] as String;
      _telemetryByBin[binId] = PoubelleTelemetry(
        binId: binId,
        wasteType: m['type'] as String,
        fillPct: (m['fill_pct'] as num).toInt(),
        weightKg: (m['weight_kg'] as num).toDouble(),
        lidOpen: m['lid_open'] == true,
        gasPpm: (m['gas_ppm'] as num).toInt(),
        batteryPct: (m['battery_pct'] as num).toInt(),
        tempC: (m['temp_c'] as num).toDouble(),
        humidity: (m['humidity'] as num).toDouble(),
      );
    }

    final st = snap['status'] as Map<String, dynamic>;
    _status = PoubelleStatus(
      binId: st['bin_id'] as String,
      online: st['online'] == true,
      mode: st['mode'] as String,
      collectionDue: st['collection_due'] == true,
      alarmOn: st['alarm_on'] == true,
    );

    for (final a in snap['alerts_recent'] as List) {
      final m = a as Map<String, dynamic>;
      _alerts.add(PoubelleAlert(binId: m['bin_id'] as String, alert: m['alert'] as String));
    }

    final now = DateTime.now();
    for (final entry in hist.entries) {
      final binId = entry.key;
      final samples = entry.value as List;
      final list = _historyByBin.putIfAbsent(binId, () => []);
      for (final s in samples) {
        final m = s as Map<String, dynamic>;
        final mins = (m['minutes_ago'] as num?)?.toInt() ?? 0;
        list.add(FillSample(
          at: now.subtract(Duration(minutes: mins)),
          fillPct: (m['fill_pct'] as num).toInt(),
          weightKg: (m['weight_kg'] as num).toDouble(),
          gasPpm: (m['gas_ppm'] as num).toInt(),
        ));
      }
    }
  }

  void _recordHistory(PoubelleTelemetry t) {
    final list = _historyByBin.putIfAbsent(t.binId, () => []);
    list.add(FillSample(
      at: DateTime.now(),
      fillPct: t.fillPct,
      weightKg: t.weightKg,
      gasPpm: t.gasPpm,
    ));
    if (list.length > 40) list.removeAt(0);
  }

  PoubelleTelemetryView? _viewFor(String id) {
    final t = _telemetryByBin[id];
    if (t == null) return null;
    return PoubelleTelemetryView(
      binId: t.binId,
      wasteType: t.wasteType,
      fillPct: t.fillPct,
      weightKg: t.weightKg,
      lidOpen: t.lidOpen,
      gasPpm: t.gasPpm,
      batteryPct: t.batteryPct,
    );
  }

  void _refreshLocalAi() {
    final all = <String, PoubelleTelemetryView>{};
    for (final e in _telemetryByBin.entries) {
      final v = _viewFor(e.key);
      if (v != null) all[e.key] = v;
    }
    _localAi = PoubelleAiEngine.analyze(
      binId: _selectedBin,
      current: _viewFor(_selectedBin),
      history: _historyByBin[_selectedBin] ?? [],
      allBins: all,
    );
  }

  Future<void> _fetchCloudAi() async {
    final url = _aiApiCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _aiError = 'URL poubelle-api requise (ex. http://IP:5150)');
      return;
    }
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final client = PoubelleAiClient(url);
      final insights = await client.fetchInsights(binId: _selectedBin);
      if (mounted) setState(() => _cloudAi = insights);
    } catch (e) {
      if (mounted) setState(() => _aiError = e.toString());
    } finally {
      if (mounted) setState(() => _aiBusy = false);
    }
  }

  @override
  void dispose() {
    _telSub?.cancel();
    _statusSub?.cancel();
    _alertSub?.cancel();
    _mqtt.dispose();
    _brokerCtrl.dispose();
    _portCtrl.dispose();
    _aiApiCtrl.dispose();
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
        _error = 'Indiquez l\'IP du broker Mosquitto';
        _busy = false;
      });
      return;
    }
    try {
      await _mqtt.connect(host: host, port: port);
      _brokerLabel = '$host:$port';
      await _telSub?.cancel();
      _telSub = _mqtt.telemetryStream.listen((t) {
        if (mounted) {
          setState(() {
            _telemetryByBin[t.binId] = t;
            _recordHistory(t);
            if (t.binId == _selectedBin) _refreshLocalAi();
          });
        }
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
            if (_alerts.length > 25) _alerts.removeLast();
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
    if (mounted) setState(() => _brokerLabel = null);
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

  String _binName(String id) {
    for (final b in _bins) {
      if (b.id == id) return b.name;
    }
    return id;
  }

  Color _fillColor(int fill) {
    if (fill >= 90) return const Color(0xFFB91C1C);
    if (fill >= 75) return const Color(0xFFD97706);
    return const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    final current = _telemetryByBin[_selectedBin];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('El Jezi — Smart Poubelle'),
          centerTitle: true,
          backgroundColor: const Color(0xFF15803D),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.delete_outline), text: 'Parc'),
              Tab(icon: Icon(Icons.tune), text: 'Commandes'),
              Tab(icon: Icon(Icons.warning_amber), text: 'Alertes'),
              Tab(icon: Icon(Icons.psychology), text: 'IA'),
            ],
          ),
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
        body: TabBarView(
          children: [
            _parcTab(current),
            _commandsTab(),
            _alertsTab(),
            _aiTab(),
          ],
        ),
      ),
    );
  }

  Widget _parcTab(PoubelleTelemetry? current) {
    return ListView(
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
            icon: const Icon(Icons.recycling),
            label: const Text('Connecter au parc'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
          ),
          const SizedBox(height: 16),
          const Text('Mode demo hors-ligne actif', style: TextStyle(color: Colors.grey)),
        ] else if (_brokerLabel != null)
          Card(child: ListTile(leading: const Icon(Icons.wifi, color: Color(0xFF15803D)), title: Text('Connecte : $_brokerLabel'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedBin,
          decoration: const InputDecoration(labelText: 'Conteneur', border: OutlineInputBorder()),
          items: _bins.map((b) => DropdownMenuItem(value: b.id, child: Text(b.name))).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedBin = v;
                _refreshLocalAi();
              });
            }
          },
        ),
        if (_localAi != null) ...[
          const SizedBox(height: 8),
          _aiChip(_localAi!),
        ],
        if (current != null) ...[
          const SizedBox(height: 12),
          _telemetryCard(current),
        ],
        const SizedBox(height: 16),
        const Text('Tous les conteneurs', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._telemetryByBin.entries.map((e) => _binTile(e.key, e.value)),
      ],
    );
  }

  Widget _telemetryCard(PoubelleTelemetry t) {
    final color = _fillColor(t.fillPct);
    return Card(
      color: const Color(0xFFF0FDF4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_binName(t.binId), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(t.wasteType, style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: t.fillPct / 100, minHeight: 12, color: color, backgroundColor: Colors.grey.shade200),
            const SizedBox(height: 8),
            Text('${t.fillPct}% · ${t.weightKg.toStringAsFixed(1)} kg', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('${t.gasPpm}', 'Gaz ppm', Icons.air),
                _metric('${t.batteryPct}%', 'Batterie', Icons.battery_std),
                _metric('${t.tempC.toStringAsFixed(1)}°C', 'Temp', Icons.thermostat),
                _metric('${t.humidity.round()}%', 'Humidite', Icons.water_drop),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                Chip(
                  avatar: Icon(Icons.open_in_full, size: 16, color: t.lidOpen ? const Color(0xFFD97706) : Colors.grey),
                  label: Text('Couvercle ${t.lidOpen ? "ouvert" : "ferme"}', style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF15803D), size: 22),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _binTile(String id, PoubelleTelemetry t) {
    final color = _fillColor(t.fillPct);
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Text('${t.fillPct}%', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold))),
        title: Text(_binName(id)),
        subtitle: Text('${t.wasteType} · ${t.weightKg.toStringAsFixed(0)} kg'),
        trailing: t.lidOpen ? const Icon(Icons.warning_amber, color: Color(0xFFD97706)) : null,
        onTap: () => setState(() {
          _selectedBin = id;
          _refreshLocalAi();
        }),
      ),
    );
  }

  Widget _commandsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Collecte & maintenance', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _cmdBtn('EMPTY_CONFIRM', 'Vider confirme', Icons.check_circle),
            _cmdBtn('LID_LOCK', 'Fermer couvercle', Icons.lock),
            _cmdBtn('MODE_ALERT', 'Alarmes ON', Icons.notifications_active),
            _cmdBtn('STATUS', 'Actualiser', Icons.refresh),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              title: const Text('Etat module'),
              subtitle: Text('Mode ${_status!.mode} · Collecte ${_status!.collectionDue ? "due" : "OK"}'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _cmdBtn(String cmd, String label, IconData icon) {
    return FilledButton.tonalIcon(
      onPressed: () => _cmd(cmd),
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _alertsTab() {
    if (_alerts.isEmpty) return const Center(child: Text('Aucune alerte'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _alerts.length,
      itemBuilder: (_, i) {
        final a = _alerts[i];
        return Card(
          color: const Color(0xFFFEF3C7),
          child: ListTile(
            leading: const Icon(Icons.warning_amber, color: Color(0xFFD97706)),
            title: Text(a.alert),
            subtitle: Text(_binName(a.binId)),
          ),
        );
      },
    );
  }

  Widget _aiTab() {
    final active = _cloudAi ?? _localAi;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFF0FDF4),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology, color: Color(0xFF15803D)),
                    SizedBox(width: 8),
                    Text('IA collecte dechets', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ],
                ),
                SizedBox(height: 8),
                Text('Prediction remplissage, priorite collecte — locale + API cloud.', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('API poubelle-api (optionnel)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _aiApiCtrl,
                  decoration: const InputDecoration(labelText: 'URL API IA', border: OutlineInputBorder(), hintText: 'http://192.168.1.100:5150'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _aiBusy ? null : _fetchCloudAi,
                    icon: _aiBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.cloud_sync),
                    label: Text(_aiBusy ? 'Analyse…' : 'Analyser via cloud'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF15803D)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_aiError != null)
          Card(color: const Color(0xFFFEF2F2), child: ListTile(leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)), title: Text(_aiError!, style: const TextStyle(fontSize: 12)))),
        const SizedBox(height: 12),
        if (active != null) _aiCard(active, title: _cloudAi != null ? 'IA Cloud' : 'IA Locale')
        else
          const Card(child: ListTile(title: Text('En attente de donnees…'))),
        if (_cloudAi != null && _localAi != null) ...[
          const SizedBox(height: 12),
          _aiCard(_localAi!, title: 'IA Locale (comparaison)'),
        ],
      ],
    );
  }

  Widget _aiChip(PoubelleAiInsights ai) {
    final color = switch (ai.fillRisk) {
      'high' => const Color(0xFFB91C1C),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF15803D),
    };
    return Card(
      color: const Color(0xFFF0FDF4),
      child: ListTile(
        leading: Icon(Icons.psychology, color: color),
        title: Text('IA : risque ${ai.fillRisk} · priorite ${ai.collectionPriority}'),
        subtitle: Text(ai.recommendations.first),
      ),
    );
  }

  Widget _aiCard(PoubelleAiInsights ai, {required String title}) {
    final riskColor = switch (ai.fillRisk) {
      'high' => const Color(0xFFB91C1C),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF15803D),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _aiMetric('Risque', ai.fillRisk.toUpperCase(), Icons.warning, color: riskColor)),
                Expanded(child: _aiMetric('Priorite', '${ai.collectionPriority}', Icons.local_shipping)),
                Expanded(child: _aiMetric('Tendance', ai.fillTrend, Icons.trending_up)),
              ],
            ),
            if (ai.predictedFill24h != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Remplissage prevu 24h : ${ai.predictedFill24h}%', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ),
            if (ai.daysUntilFull != null)
              Text('Jours avant plein : ${ai.daysUntilFull}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            if (ai.collectNow)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Collecte recommandee maintenant', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB91C1C))),
              ),
            if (ai.anomalies.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Anomalies', style: TextStyle(fontWeight: FontWeight.w600)),
              ...ai.anomalies.map((a) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber, size: 18, color: Color(0xFFD97706)),
                    title: Text(a, style: const TextStyle(fontSize: 13)),
                  )),
            ],
            const SizedBox(height: 8),
            const Text('Recommandations', style: TextStyle(fontWeight: FontWeight.w600)),
            ...ai.recommendations.map((r) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF15803D)),
                  title: Text(r, style: const TextStyle(fontSize: 13)),
                )),
          ],
        ),
      ),
    );
  }

  Widget _aiMetric(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? const Color(0xFF15803D), size: 22),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}
