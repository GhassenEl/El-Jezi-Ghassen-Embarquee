import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/energy_ai_engine.dart';
import 'api/energy_ai_client.dart';
import 'mqtt/smart_energy_mqtt_client.dart';

void main() => runApp(const SmartEnergyApp());

class SmartEnergyApp extends StatelessWidget {
  const SmartEnergyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Energy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFEAB308), brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const EnergyPage(),
    );
  }
}

class SiteInfo {
  SiteInfo({required this.id, required this.name, required this.type, required this.capacityKw});

  factory SiteInfo.fromJson(Map<String, dynamic> j) => SiteInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        capacityKw: (j['capacity_kw'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String name;
  final String type;
  final double capacityKw;
}

class EnergyPage extends StatefulWidget {
  const EnergyPage({super.key});

  @override
  State<EnergyPage> createState() => _EnergyPageState();
}

class _EnergyPageState extends State<EnergyPage> {
  final _mqtt = SmartEnergyMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');
  final _aiApiCtrl = TextEditingController(text: 'http://192.168.1.100:5170');

  List<SiteInfo> _sites = [];
  String _selectedSite = 'lac-solar';
  final Map<String, EnergyTelemetry> _telemetryBySite = {};
  EnergyStatus? _status;
  final Map<String, List<LoadSample>> _historyBySite = {};
  final List<EnergyAlert> _alerts = [];

  EnergyAiInsights? _localAi;
  EnergyAiInsights? _cloudAi;
  String? _aiError;
  bool _aiBusy = false;
  String? _error;
  bool _busy = false;
  String? _brokerLabel;

  StreamSubscription<EnergyTelemetry>? _telSub;
  StreamSubscription<EnergyStatus>? _statusSub;
  StreamSubscription<EnergyAlert>? _alertSub;

  bool get _connected => _mqtt.isConnected;

  @override
  void initState() {
    super.initState();
    _loadSeed();
  }

  Future<void> _loadSeed() async {
    final sitesRaw = await rootBundle.loadString('assets/sites.json');
    final snapRaw = await rootBundle.loadString('assets/demo_snapshot.json');
    final histRaw = await rootBundle.loadString('assets/demo_history.json');
    final sitesData = jsonDecode(sitesRaw) as Map<String, dynamic>;
    final snap = jsonDecode(snapRaw) as Map<String, dynamic>;
    final hist = jsonDecode(histRaw) as Map<String, dynamic>;
    setState(() {
      _sites = (sitesData['sites'] as List).map((e) => SiteInfo.fromJson(e as Map<String, dynamic>)).toList();
      _seedFromJson(snap, hist);
      _refreshLocalAi();
    });
  }

  void _seedFromJson(Map<String, dynamic> snap, Map<String, dynamic> hist) {
    _telemetryBySite.clear();
    _historyBySite.clear();
    _alerts.clear();

    for (final row in snap['sites_live'] as List) {
      final m = row as Map<String, dynamic>;
      final siteId = m['site_id'] as String;
      _telemetryBySite[siteId] = EnergyTelemetry(
        siteId: siteId,
        loadKw: (m['load_kw'] as num).toDouble(),
        solarKw: (m['solar_kw'] as num).toDouble(),
        gridKw: (m['grid_kw'] as num).toDouble(),
        batteryPct: (m['battery_pct'] as num).toInt(),
        costTndH: (m['cost_tnd_h'] as num).toDouble(),
        peak: m['peak'] == true,
        tempC: (m['temp_c'] as num).toDouble(),
        humidity: 45,
      );
    }

    final st = snap['status'] as Map<String, dynamic>;
    _status = EnergyStatus(
      siteId: st['site_id'] as String,
      online: st['online'] == true,
      mode: st['mode'] as String,
      gridConnected: st['grid_connected'] == true,
    );

    for (final a in snap['alerts_recent'] as List) {
      final m = a as Map<String, dynamic>;
      _alerts.add(EnergyAlert(siteId: m['site_id'] as String, alert: m['alert'] as String));
    }

    final now = DateTime.now();
    for (final entry in hist.entries) {
      final siteId = entry.key;
      final list = _historyBySite.putIfAbsent(siteId, () => []);
      for (final s in entry.value as List) {
        final m = s as Map<String, dynamic>;
        list.add(LoadSample(
          at: now.subtract(Duration(minutes: (m['minutes_ago'] as num?)?.toInt() ?? 0)),
          loadKw: (m['load_kw'] as num).toDouble(),
          solarKw: (m['solar_kw'] as num).toDouble(),
          gridKw: (m['grid_kw'] as num).toDouble(),
        ));
      }
    }
  }

  void _recordHistory(EnergyTelemetry t) {
    final list = _historyBySite.putIfAbsent(t.siteId, () => []);
    list.add(LoadSample(at: DateTime.now(), loadKw: t.loadKw, solarKw: t.solarKw, gridKw: t.gridKw));
    if (list.length > 40) list.removeAt(0);
  }

  EnergySiteView? _viewFor(String id) {
    final t = _telemetryBySite[id];
    if (t == null) return null;
    return EnergySiteView(
      siteId: t.siteId,
      loadKw: t.loadKw,
      solarKw: t.solarKw,
      gridKw: t.gridKw,
      batteryPct: t.batteryPct,
      costTndH: t.costTndH,
      peak: t.peak,
    );
  }

  void _refreshLocalAi() {
    _localAi = EnergyAiEngine.analyze(
      siteId: _selectedSite,
      current: _viewFor(_selectedSite),
      history: _historyBySite[_selectedSite] ?? [],
    );
  }

  Future<void> _fetchCloudAi() async {
    final url = _aiApiCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _aiError = 'URL energy-api requise (ex. http://IP:5170)');
      return;
    }
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final insights = await EnergyAiClient(url).fetchInsights(siteId: _selectedSite);
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
            _telemetryBySite[t.siteId] = t;
            _recordHistory(t);
            if (t.siteId == _selectedSite) _refreshLocalAi();
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

  String _siteName(String id) {
    for (final s in _sites) {
      if (s.id == id) return s.name;
    }
    return id;
  }

  Color _riskColor(String risk) => switch (risk) {
        'high' => const Color(0xFFB91C1C),
        'medium' => const Color(0xFFD97706),
        _ => const Color(0xFFCA8A04),
      };

  @override
  Widget build(BuildContext context) {
    final current = _telemetryBySite[_selectedSite];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('El Jezi — Smart Energy'),
          centerTitle: true,
          backgroundColor: const Color(0xFFCA8A04),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.bolt), text: 'Energie'),
              Tab(icon: Icon(Icons.tune), text: 'Controles'),
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
              IconButton(onPressed: _connected ? _disconnect : _connect, icon: Icon(_connected ? Icons.cloud_done : Icons.cloud_off)),
          ],
        ),
        body: TabBarView(children: [_energyTab(current), _controlsTab(), _alertsTab(), _aiTab()]),
      ),
    );
  }

  Widget _energyTab(EnergyTelemetry? current) {
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
            icon: const Icon(Icons.bolt),
            label: const Text('Connecter aux sites'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFCA8A04)),
          ),
          const SizedBox(height: 16),
          const Text('Mode demo hors-ligne actif', style: TextStyle(color: Colors.grey)),
        ] else if (_brokerLabel != null)
          Card(child: ListTile(leading: const Icon(Icons.wifi, color: Color(0xFFCA8A04)), title: Text('Connecte : $_brokerLabel'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedSite,
          decoration: const InputDecoration(labelText: 'Site', border: OutlineInputBorder()),
          items: _sites.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedSite = v;
                _refreshLocalAi();
              });
            }
          },
        ),
        if (_localAi != null) ...[
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFFFEFCE8),
            child: ListTile(
              leading: Icon(Icons.psychology, color: _riskColor(_localAi!.costRisk)),
              title: Text('IA : efficacite ${_localAi!.efficiencyScore}/100'),
              subtitle: Text(_localAi!.recommendations.first),
            ),
          ),
        ],
        if (current != null) ...[
          const SizedBox(height: 12),
          _telemetryCard(current),
        ],
        const SizedBox(height: 16),
        const Text('Tous les sites', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._telemetryBySite.entries.map((e) => _siteTile(e.key, e.value)),
      ],
    );
  }

  Widget _telemetryCard(EnergyTelemetry t) {
    final coverage = t.loadKw > 0 ? (t.solarKw / t.loadKw * 100).round() : 0;
    return Card(
      color: const Color(0xFFFEFCE8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_siteName(t.siteId), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (t.peak)
              const Chip(label: Text('PIC', style: TextStyle(fontSize: 11)), backgroundColor: Color(0xFFFEF3C7)),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('${t.loadKw.toStringAsFixed(0)} kW', 'Charge', Icons.bolt),
                _metric('${t.solarKw.toStringAsFixed(0)} kW', 'Solaire', Icons.solar_power),
                _metric('${t.gridKw.toStringAsFixed(0)} kW', 'Reseau', Icons.power),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('$coverage%', 'Couverture', Icons.wb_sunny),
                _metric('${t.batteryPct}%', 'Batterie', Icons.battery_charging_full),
                _metric('${t.costTndH.toStringAsFixed(1)} TND/h', 'Cout', Icons.payments),
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
          Icon(icon, color: const Color(0xFFCA8A04), size: 22),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _siteTile(String id, EnergyTelemetry t) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFFEF9C3),
          child: Icon(t.peak ? Icons.warning : Icons.bolt, color: const Color(0xFFCA8A04), size: 20),
        ),
        title: Text(_siteName(id)),
        subtitle: Text('${t.loadKw.toStringAsFixed(0)} kW · solaire ${t.solarKw.toStringAsFixed(0)} kW'),
        trailing: Text('${t.costTndH.toStringAsFixed(0)} TND/h', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        onTap: () => setState(() {
          _selectedSite = id;
          _refreshLocalAi();
        }),
      ),
    );
  }

  Widget _controlsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Modes energie', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _cmdBtn('MODE_ECO', 'Mode ECO', Icons.eco),
            _cmdBtn('MODE_AUTO', 'Mode AUTO', Icons.autorenew),
            _cmdBtn('BATT_CHARGE', 'Charge batterie', Icons.battery_charging_full),
            _cmdBtn('STATUS', 'Actualiser', Icons.refresh),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              title: const Text('Etat site'),
              subtitle: Text('Mode ${_status!.mode} · Reseau ${_status!.gridConnected ? "connecte" : "deconnecte"}'),
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
            subtitle: Text(_siteName(a.siteId)),
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
          color: const Color(0xFFFEFCE8),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Icon(Icons.psychology, color: Color(0xFFCA8A04)), SizedBox(width: 8), Text('IA optimisation energetique', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))]),
                SizedBox(height: 8),
                Text('Pics, solaire, batteries — analyse locale + API cloud.', style: TextStyle(fontSize: 13)),
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
                const Text('API energy-api (optionnel)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(controller: _aiApiCtrl, decoration: const InputDecoration(labelText: 'URL API IA', border: OutlineInputBorder(), hintText: 'http://192.168.1.100:5170')),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _aiBusy ? null : _fetchCloudAi,
                    icon: _aiBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_sync),
                    label: Text(_aiBusy ? 'Analyse…' : 'Analyser via cloud'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFFCA8A04)),
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
      ],
    );
  }

  Widget _aiCard(EnergyAiInsights ai, {required String title}) {
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
                Expanded(child: _aiMetric('Efficacite', '${ai.efficiencyScore}', Icons.speed)),
                Expanded(child: _aiMetric('Cout', ai.costRisk.toUpperCase(), Icons.payments, color: _riskColor(ai.costRisk))),
                Expanded(child: _aiMetric('Tendance', ai.loadTrend, Icons.trending_up)),
              ],
            ),
            if (ai.solarCoveragePct != null)
              Padding(padding: const EdgeInsets.only(top: 10), child: Text('Couverture solaire : ${ai.solarCoveragePct}%', style: TextStyle(color: Colors.grey.shade700, fontSize: 13))),
            if (ai.predictedLoad2h != null)
              Text('Charge prevue 2h : ${ai.predictedLoad2h!.toStringAsFixed(0)} kW', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            if (ai.ecoModeRecommended)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('Mode ECO recommande', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFFB91C1C)))),
            if (ai.anomalies.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Anomalies', style: TextStyle(fontWeight: FontWeight.w600)),
              ...ai.anomalies.map((a) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.warning_amber, size: 18, color: Color(0xFFD97706)), title: Text(a, style: const TextStyle(fontSize: 13)))),
            ],
            const SizedBox(height: 8),
            const Text('Recommandations', style: TextStyle(fontWeight: FontWeight.w600)),
            ...ai.recommendations.map((r) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFCA8A04)), title: Text(r, style: const TextStyle(fontSize: 13)))),
          ],
        ),
      ),
    );
  }

  Widget _aiMetric(String label, String value, IconData icon, {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? const Color(0xFFCA8A04), size: 22),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}
