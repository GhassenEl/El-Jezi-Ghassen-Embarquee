import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/parking_ai_engine.dart';
import 'api/parking_ai_client.dart';
import 'mqtt/smart_parking_mqtt_client.dart';

void main() => runApp(const SmartParkingApp());

class SmartParkingApp extends StatelessWidget {
  const SmartParkingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Parking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB), brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const ParkingPage(),
    );
  }
}

class LotInfo {
  LotInfo({required this.id, required this.name, required this.type, required this.priceHour});

  factory LotInfo.fromJson(Map<String, dynamic> j) => LotInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        type: j['type']?.toString() ?? '',
        priceHour: (j['price_hour_tnd'] as num?)?.toDouble() ?? 0,
      );

  final String id;
  final String name;
  final String type;
  final double priceHour;
}

class ParkingPage extends StatefulWidget {
  const ParkingPage({super.key});

  @override
  State<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends State<ParkingPage> {
  final _mqtt = SmartParkingMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');
  final _aiApiCtrl = TextEditingController(text: 'http://192.168.1.100:5160');

  List<LotInfo> _lots = [];
  String _selectedLot = 'lac-nord';
  final Map<String, ParkingTelemetry> _telemetryByLot = {};
  ParkingStatus? _status;
  final Map<String, List<OccSample>> _historyByLot = {};
  final List<ParkingAlert> _alerts = [];

  ParkingAiInsights? _localAi;
  ParkingAiInsights? _cloudAi;
  String? _aiError;
  bool _aiBusy = false;
  String? _error;
  bool _busy = false;
  String? _brokerLabel;

  StreamSubscription<ParkingTelemetry>? _telSub;
  StreamSubscription<ParkingStatus>? _statusSub;
  StreamSubscription<ParkingAlert>? _alertSub;

  bool get _connected => _mqtt.isConnected;

  @override
  void initState() {
    super.initState();
    _loadSeed();
  }

  Future<void> _loadSeed() async {
    final lotsRaw = await rootBundle.loadString('assets/lots.json');
    final snapRaw = await rootBundle.loadString('assets/demo_snapshot.json');
    final histRaw = await rootBundle.loadString('assets/demo_history.json');
    final lotsData = jsonDecode(lotsRaw) as Map<String, dynamic>;
    final snap = jsonDecode(snapRaw) as Map<String, dynamic>;
    final hist = jsonDecode(histRaw) as Map<String, dynamic>;
    setState(() {
      _lots = (lotsData['lots'] as List).map((e) => LotInfo.fromJson(e as Map<String, dynamic>)).toList();
      _seedFromJson(snap, hist);
      _refreshLocalAi();
    });
  }

  void _seedFromJson(Map<String, dynamic> snap, Map<String, dynamic> hist) {
    _telemetryByLot.clear();
    _historyByLot.clear();
    _alerts.clear();

    for (final row in snap['lots_live'] as List) {
      final m = row as Map<String, dynamic>;
      final lotId = m['lot_id'] as String;
      _telemetryByLot[lotId] = ParkingTelemetry(
        lotId: lotId,
        spotsTotal: (m['spots_total'] as num).toInt(),
        spotsFree: (m['spots_free'] as num).toInt(),
        occupancyPct: (m['occupancy_pct'] as num).toInt(),
        evFree: (m['ev_free'] as num).toInt(),
        gateOpen: m['gate_open'] == true,
        tempC: (m['temp_c'] as num).toDouble(),
        humidity: 50,
      );
    }

    final st = snap['status'] as Map<String, dynamic>;
    _status = ParkingStatus(
      lotId: st['lot_id'] as String,
      online: st['online'] == true,
      mode: st['mode'] as String,
      gateOpen: st['gate_open'] == true,
    );

    for (final a in snap['alerts_recent'] as List) {
      final m = a as Map<String, dynamic>;
      _alerts.add(ParkingAlert(lotId: m['lot_id'] as String, alert: m['alert'] as String));
    }

    final now = DateTime.now();
    for (final entry in hist.entries) {
      final lotId = entry.key;
      final list = _historyByLot.putIfAbsent(lotId, () => []);
      for (final s in entry.value as List) {
        final m = s as Map<String, dynamic>;
        list.add(OccSample(
          at: now.subtract(Duration(minutes: (m['minutes_ago'] as num?)?.toInt() ?? 0)),
          occupancyPct: (m['occupancy_pct'] as num).toInt(),
          spotsFree: (m['spots_free'] as num).toInt(),
        ));
      }
    }
  }

  void _recordHistory(ParkingTelemetry t) {
    final list = _historyByLot.putIfAbsent(t.lotId, () => []);
    list.add(OccSample(at: DateTime.now(), occupancyPct: t.occupancyPct, spotsFree: t.spotsFree));
    if (list.length > 40) list.removeAt(0);
  }

  ParkingLotView? _viewFor(String id) {
    final t = _telemetryByLot[id];
    if (t == null) return null;
    return ParkingLotView(
      lotId: t.lotId,
      spotsTotal: t.spotsTotal,
      spotsFree: t.spotsFree,
      occupancyPct: t.occupancyPct,
      evFree: t.evFree,
      gateOpen: t.gateOpen,
    );
  }

  void _refreshLocalAi() {
    final all = <String, ParkingLotView>{};
    for (final e in _telemetryByLot.entries) {
      final v = _viewFor(e.key);
      if (v != null) all[e.key] = v;
    }
    _localAi = ParkingAiEngine.analyze(
      lotId: _selectedLot,
      current: _viewFor(_selectedLot),
      history: _historyByLot[_selectedLot] ?? [],
      allLots: all,
    );
  }

  Future<void> _fetchCloudAi() async {
    final url = _aiApiCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _aiError = 'URL parking-api requise (ex. http://IP:5160)');
      return;
    }
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final insights = await ParkingAiClient(url).fetchInsights(lotId: _selectedLot);
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
            _telemetryByLot[t.lotId] = t;
            _recordHistory(t);
            if (t.lotId == _selectedLot) _refreshLocalAi();
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

  String _lotName(String id) {
    for (final l in _lots) {
      if (l.id == id) return l.name;
    }
    return id;
  }

  Color _occColor(int occ) {
    if (occ >= 90) return const Color(0xFFB91C1C);
    if (occ >= 75) return const Color(0xFFD97706);
    return const Color(0xFF2563EB);
  }

  @override
  Widget build(BuildContext context) {
    final current = _telemetryByLot[_selectedLot];

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('El Jezi — Smart Parking'),
          centerTitle: true,
          backgroundColor: const Color(0xFF1D4ED8),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.local_parking), text: 'Parkings'),
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
              IconButton(
                onPressed: _connected ? _disconnect : _connect,
                icon: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
              ),
          ],
        ),
        body: TabBarView(
          children: [_parkingsTab(current), _controlsTab(), _alertsTab(), _aiTab()],
        ),
      ),
    );
  }

  Widget _parkingsTab(ParkingTelemetry? current) {
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
            icon: const Icon(Icons.local_parking),
            label: const Text('Connecter aux parkings'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8)),
          ),
          const SizedBox(height: 16),
          const Text('Mode demo hors-ligne actif', style: TextStyle(color: Colors.grey)),
        ] else if (_brokerLabel != null)
          Card(child: ListTile(leading: const Icon(Icons.wifi, color: Color(0xFF1D4ED8)), title: Text('Connecte : $_brokerLabel'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedLot,
          decoration: const InputDecoration(labelText: 'Parking', border: OutlineInputBorder()),
          items: _lots.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedLot = v;
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
        const Text('Tous les parkings', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._telemetryByLot.entries.map((e) => _lotTile(e.key, e.value)),
      ],
    );
  }

  Widget _telemetryCard(ParkingTelemetry t) {
    final color = _occColor(t.occupancyPct);
    return Card(
      color: const Color(0xFFEFF6FF),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_lotName(t.lotId), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: t.occupancyPct / 100, minHeight: 12, color: color, backgroundColor: Colors.grey.shade200),
            const SizedBox(height: 8),
            Text('${t.spotsFree} places libres / ${t.spotsTotal} · ${t.occupancyPct}% occupe', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('${t.evFree}', 'EV libres', Icons.ev_station),
                _metric(t.gateOpen ? 'Oui' : 'Non', 'Barriere', Icons.sensor_door),
                _metric('${t.tempC.toStringAsFixed(1)}°C', 'Temp', Icons.thermostat),
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
          Icon(icon, color: const Color(0xFF1D4ED8), size: 22),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _lotTile(String id, ParkingTelemetry t) {
    final color = _occColor(t.occupancyPct);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Text('${t.spotsFree}', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        ),
        title: Text(_lotName(id)),
        subtitle: Text('${t.occupancyPct}% · ${t.evFree} EV'),
        trailing: t.occupancyPct >= 90 ? const Icon(Icons.block, color: Color(0xFFB91C1C)) : null,
        onTap: () => setState(() {
          _selectedLot = id;
          _refreshLocalAi();
        }),
      ),
    );
  }

  Widget _controlsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Barrieres', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _cmdBtn('GATE_OPEN', 'Ouvrir', Icons.lock_open),
            _cmdBtn('GATE_CLOSE', 'Fermer', Icons.lock),
            _cmdBtn('STATUS', 'Actualiser', Icons.refresh),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              title: const Text('Etat parking'),
              subtitle: Text('Mode ${_status!.mode} · Barriere ${_status!.gateOpen ? "ouverte" : "fermee"}'),
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
            subtitle: Text(_lotName(a.lotId)),
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
          color: const Color(0xFFEFF6FF),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology, color: Color(0xFF1D4ED8)),
                    SizedBox(width: 8),
                    Text('IA parking intelligent', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ],
                ),
                SizedBox(height: 8),
                Text('Recommandation place, prediction saturation, alternative.', style: TextStyle(fontSize: 13)),
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
                const Text('API parking-api (optionnel)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _aiApiCtrl,
                  decoration: const InputDecoration(labelText: 'URL API IA', border: OutlineInputBorder(), hintText: 'http://192.168.1.100:5160'),
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
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1D4ED8)),
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

  Widget _aiChip(ParkingAiInsights ai) {
    final color = switch (ai.occupancyRisk) {
      'high' => const Color(0xFFB91C1C),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF1D4ED8),
    };
    return Card(
      color: const Color(0xFFEFF6FF),
      child: ListTile(
        leading: Icon(Icons.psychology, color: color),
        title: Text('IA : risque ${ai.occupancyRisk} · ${ai.navigateHere ? "Recommande" : "Eviter"}'),
        subtitle: Text(ai.recommendations.first),
      ),
    );
  }

  Widget _aiCard(ParkingAiInsights ai, {required String title}) {
    final riskColor = switch (ai.occupancyRisk) {
      'high' => const Color(0xFFB91C1C),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF1D4ED8),
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
                Expanded(child: _aiMetric('Risque', ai.occupancyRisk.toUpperCase(), Icons.warning, color: riskColor)),
                Expanded(child: _aiMetric('Tendance', ai.occupancyTrend, Icons.trending_up)),
                Expanded(child: _aiMetric('Naviguer', ai.navigateHere ? 'OUI' : 'NON', Icons.navigation)),
              ],
            ),
            if (ai.predictedOcc2h != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Occupation prevue 2h : ${ai.predictedOcc2h}%', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ),
            if (ai.bestAlternative != null)
              Text('Alternative : ${ai.bestAlternative}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                  leading: const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF1D4ED8)),
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
        Icon(icon, color: color ?? const Color(0xFF1D4ED8), size: 22),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}
