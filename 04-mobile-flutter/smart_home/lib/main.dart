import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai/home_ai_engine.dart';
import 'api/home_ai_client.dart';
import 'mqtt/smart_home_mqtt_client.dart';

void main() => runApp(const SmartHomeApp());

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF059669), brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class ZoneInfo {
  ZoneInfo({required this.id, required this.name, required this.targetTemp, this.description = ''});

  factory ZoneInfo.fromJson(Map<String, dynamic> j) => ZoneInfo(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        targetTemp: (j['target_temp'] as num?)?.toDouble() ?? 22,
        description: j['description']?.toString() ?? '',
      );

  final String id;
  final String name;
  final double targetTemp;
  final String description;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _mqtt = SmartHomeMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');
  final _aiApiCtrl = TextEditingController(text: 'http://192.168.1.100:8120');

  List<ZoneInfo> _zones = [];
  String _selectedZone = 'salon';

  final Map<String, HomeTelemetry> _telemetryByZone = {};
  HomeStatus? _status;
  final Map<String, List<TelemetrySample>> _historyByZone = {};
  final List<HomeAlert> _alerts = [];

  HomeAiInsights? _localAi;
  HomeAiInsights? _cloudAi;
  String? _aiError;
  bool _aiBusy = false;

  String? _error;
  bool _busy = false;
  String? _brokerLabel;

  StreamSubscription<HomeTelemetry>? _telSub;
  StreamSubscription<HomeStatus>? _statusSub;
  StreamSubscription<HomeAlert>? _alertSub;

  bool get _connected => _mqtt.isConnected;

  @override
  void initState() {
    super.initState();
    _loadSeed();
  }

  Future<void> _loadSeed() async {
    final raw = await rootBundle.loadString('assets/zones.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      _zones = (data['zones'] as List).map((e) => ZoneInfo.fromJson(e as Map<String, dynamic>)).toList();
      _seedDemo();
      _refreshLocalAi();
    });
  }

  void _seedDemo() {
    final demos = [
      ('salon', 22.5, 48.0, 420, false, false, true, false, 125),
      ('chambre', 20.2, 52.0, 80, false, false, false, false, 35),
      ('cuisine', 21.8, 55.0, 310, true, false, true, false, 95),
      ('bureau', 22.0, 45.0, 520, true, false, true, false, 110),
      ('garage', 18.5, 60.0, 40, false, true, false, false, 55),
    ];
    for (final d in demos) {
      _telemetryByZone[d.$1] = HomeTelemetry(
        zone: d.$1,
        tempC: d.$2,
        humidity: d.$3,
        lux: d.$4,
        motion: d.$5,
        doorOpen: d.$6,
        lightOn: d.$7,
        heatOn: d.$8,
        powerW: d.$9,
      );
    }
    _status = const HomeStatus(
      zone: 'salon',
      online: true,
      mode: 'HOME',
      targetTemp: 22,
      alarmOn: true,
      doorLocked: true,
    );
  }

  void _recordHistory(HomeTelemetry t) {
    final list = _historyByZone.putIfAbsent(t.zone, () => []);
    list.add(TelemetrySample(
      at: DateTime.now(),
      tempC: t.tempC,
      humidity: t.humidity,
      powerW: t.powerW,
      lux: t.lux,
    ));
    if (list.length > 40) list.removeAt(0);
  }

  double _targetForZone(String id) {
    for (final z in _zones) {
      if (z.id == id) return z.targetTemp;
    }
    return 22;
  }

  void _refreshLocalAi() {
    _localAi = HomeAiEngine.analyze(
      zone: _selectedZone,
      current: _telemetryByZone[_selectedZone],
      status: _status,
      history: _historyByZone[_selectedZone] ?? [],
      allZones: _telemetryByZone,
      targetTemp: _targetForZone(_selectedZone),
    );
  }

  Future<void> _fetchCloudAi() async {
    final url = _aiApiCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _aiError = 'URL home-api requise (ex. http://IP:8120)');
      return;
    }
    setState(() {
      _aiBusy = true;
      _aiError = null;
    });
    try {
      final client = HomeAiClient(url);
      final mode = _status?.mode ?? 'HOME';
      final insights = await client.fetchInsights(zone: _selectedZone, mode: mode);
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
            _telemetryByZone[t.zone] = t;
            _recordHistory(t);
            if (t.zone == _selectedZone) _refreshLocalAi();
          });
        }
      });
      await _statusSub?.cancel();
      _statusSub = _mqtt.statusStream.listen((s) {
        if (mounted) {
          setState(() {
            _status = s;
            _refreshLocalAi();
          });
        }
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

  String _zoneName(String id) {
    for (final z in _zones) {
      if (z.id == id) return z.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final current = _telemetryByZone[_selectedZone];
    final status = _status;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('El Jezi — Smart Home'),
          centerTitle: true,
          backgroundColor: const Color(0xFF047857),
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(icon: Icon(Icons.home), text: 'Maison'),
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
          children: [
            _maisonTab(current, status),
            _controlsTab(status),
            _alertsTab(),
            _aiTab(),
          ],
        ),
      ),
    );
  }

  Widget _maisonTab(HomeTelemetry? current, HomeStatus? status) {
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
            icon: const Icon(Icons.home),
            label: const Text('Connecter a la maison'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
          ),
          const SizedBox(height: 16),
          const Text('Mode demo hors-ligne actif', style: TextStyle(color: Colors.grey)),
        ] else if (_brokerLabel != null)
          Card(child: ListTile(leading: const Icon(Icons.wifi, color: Color(0xFF047857)), title: Text('Connecte : $_brokerLabel'))),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedZone,
          decoration: const InputDecoration(labelText: 'Zone', border: OutlineInputBorder()),
          items: _zones.map((z) => DropdownMenuItem(value: z.id, child: Text(z.name))).toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _selectedZone = v;
                _refreshLocalAi();
              });
            }
          },
        ),
        if (status != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(Icons.shield, color: status.mode == 'AWAY' ? Colors.orange : const Color(0xFF047857)),
              title: Text('Mode ${status.mode}'),
              subtitle: Text('Cible ${status.targetTemp}°C · Alarme ${status.alarmOn ? "ON" : "OFF"} · Serrure ${status.doorLocked ? "verrouillee" : "ouverte"}'),
            ),
          ),
        ],
        if (_localAi != null) ...[
          const SizedBox(height: 8),
          _aiSummaryChip(_localAi!),
        ],
        if (current != null) ...[
          const SizedBox(height: 12),
          _telemetryCard(current),
        ],
        const SizedBox(height: 16),
        const Text('Toutes les zones', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ..._telemetryByZone.entries.map((e) => _zoneTile(e.key, e.value)),
      ],
    );
  }

  Widget _telemetryCard(HomeTelemetry t) {
    return Card(
      color: const Color(0xFFECFDF5),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_zoneName(t.zone), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            Row(
              children: [
                _metric('${t.tempC.toStringAsFixed(1)}°C', 'Temp', Icons.thermostat),
                _metric('${t.humidity.round()}%', 'Humidite', Icons.water_drop),
                _metric('${t.lux}', 'Lux', Icons.light_mode),
                _metric('${t.powerW}W', 'Puissance', Icons.bolt),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _chip('Mouvement', t.motion, Icons.directions_walk),
                _chip('Porte', t.doorOpen, Icons.door_front_door),
                _chip('Lumiere', t.lightOn, Icons.lightbulb),
                _chip('Chauffage', t.heatOn, Icons.local_fire_department),
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
          Icon(icon, color: const Color(0xFF047857), size: 22),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool on, IconData icon) {
    return Chip(
      avatar: Icon(icon, size: 16, color: on ? const Color(0xFF047857) : Colors.grey),
      label: Text('$label ${on ? "ON" : "OFF"}', style: const TextStyle(fontSize: 12)),
      backgroundColor: on ? const Color(0xFFD1FAE5) : Colors.grey.shade100,
    );
  }

  Widget _zoneTile(String id, HomeTelemetry t) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFFECFDF5), child: Text('${t.tempC.round()}°')),
        title: Text(_zoneName(id)),
        subtitle: Text('${t.humidity.round()}% · ${t.powerW}W · Lux ${t.lux}'),
        trailing: t.motion ? const Icon(Icons.directions_walk, color: Color(0xFF047857)) : null,
        onTap: () => setState(() {
          _selectedZone = id;
          _refreshLocalAi();
        }),
      ),
    );
  }

  Widget _controlsTab(HomeStatus? status) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Eclairage & chauffage', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _cmdBtn('LIGHT_ON', 'Lumiere ON', Icons.lightbulb),
            _cmdBtn('LIGHT_OFF', 'Lumiere OFF', Icons.lightbulb_outline),
            _cmdBtn('HEAT_ON', 'Chauffage ON', Icons.local_fire_department),
            _cmdBtn('HEAT_OFF', 'Chauffage OFF', Icons.ac_unit),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Modes domotiques', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _cmdBtn('MODE_HOME', 'Maison', Icons.home),
            _cmdBtn('MODE_AWAY', 'Absent', Icons.directions_walk),
            _cmdBtn('MODE_SLEEP', 'Nuit', Icons.bedtime),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Securite', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _cmdBtn('LOCK_ON', 'Verrouiller', Icons.lock),
            _cmdBtn('LOCK_OFF', 'Deverrouiller', Icons.lock_open),
            _cmdBtn('ALARM_ON', 'Alarme ON', Icons.notifications_active),
            _cmdBtn('ALARM_OFF', 'Alarme OFF', Icons.notifications_off),
            _cmdBtn('DOOR_TOGGLE', 'Porte', Icons.door_sliding),
            _cmdBtn('STATUS', 'Actualiser', Icons.refresh),
          ],
        ),
        if (status != null) ...[
          const SizedBox(height: 20),
          Card(
            child: ListTile(
              title: const Text('Etat actuel'),
              subtitle: Text('Mode ${status.mode} · ${status.targetTemp}°C cible'),
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
    if (_alerts.isEmpty) {
      return const Center(child: Text('Aucune alerte'));
    }
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
            subtitle: Text(_zoneName(a.zone)),
          ),
        );
      },
    );
  }

  Widget _aiTab() {
    final local = _localAi;
    final cloud = _cloudAi;
    final active = cloud ?? local;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFECFDF5),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology, color: Color(0xFF047857)),
                    SizedBox(width: 8),
                    Text('Assistant IA domotique', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ],
                ),
                SizedBox(height: 8),
                Text('Confort, securite, energie — analyse locale + API cloud.', style: TextStyle(fontSize: 13)),
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
                const Text('API home-api (optionnel)', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _aiApiCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL cloud IA',
                    border: OutlineInputBorder(),
                    hintText: 'http://192.168.1.100:8120',
                  ),
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
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF047857)),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_aiError != null)
          Card(
            color: const Color(0xFFFEF2F2),
            child: ListTile(leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)), title: Text(_aiError!, style: const TextStyle(fontSize: 12))),
          ),
        const SizedBox(height: 12),
        if (active != null) _aiInsightsCard(active, title: cloud != null ? 'IA Cloud' : 'IA Locale') else
          const Card(child: ListTile(title: Text('En attente de donnees…'))),
        if (cloud != null && local != null) ...[
          const SizedBox(height: 12),
          _aiInsightsCard(local, title: 'IA Locale (comparaison)'),
        ],
      ],
    );
  }

  Widget _aiSummaryChip(HomeAiInsights ai) {
    final color = switch (ai.securityRisk) {
      'high' => const Color(0xFFB91C1C),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF047857),
    };
    return Card(
      color: const Color(0xFFECFDF5),
      child: ListTile(
        leading: Icon(Icons.psychology, color: color),
        title: Text('IA : securite ${ai.securityRisk} · confort ${ai.comfortScore}/100'),
        subtitle: Text(ai.recommendations.first),
      ),
    );
  }

  Widget _aiInsightsCard(HomeAiInsights ai, {required String title}) {
    final riskColor = switch (ai.securityRisk) {
      'high' => const Color(0xFFB91C1C),
      'medium' => const Color(0xFFD97706),
      _ => const Color(0xFF047857),
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
                Expanded(child: _aiMetric('Confort', '${ai.comfortScore}', Icons.event_seat)),
                Expanded(child: _aiMetric('Energie', '${ai.energyScore}', Icons.bolt)),
                Expanded(child: _aiMetric('Securite', ai.securityRisk.toUpperCase(), Icons.shield, color: riskColor)),
              ],
            ),
            if (ai.predictedTempC != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text('Temp prevue : ${ai.predictedTempC}°C · tendance ${ai.tempTrend}', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
              ),
            if (ai.powerWAvg != null)
              Text('Puissance moy. : ${ai.powerWAvg} W', style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            if (ai.autoModeRecommended != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Mode recommande : ${ai.autoModeRecommended}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
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
                  leading: const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFF047857)),
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
        Icon(icon, color: color ?? const Color(0xFF047857), size: 22),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }
}
