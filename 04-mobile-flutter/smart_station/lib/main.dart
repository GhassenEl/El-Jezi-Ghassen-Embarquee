import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mqtt/smart_station_mqtt_client.dart';

void main() => runApp(const SmartStationApp());

class SmartStationApp extends StatelessWidget {
  const SmartStationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Station',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D4ED8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const StationHomePage(),
    );
  }
}

class LineInfo {
  LineInfo({required this.id, required this.name, required this.type, required this.color});

  final String id;
  final String name;
  final String type;
  final Color color;

  factory LineInfo.fromJson(Map<String, dynamic> j) {
    final hex = (j['color'] as String).replaceFirst('#', '');
    final c = Color(int.parse('FF$hex', radix: 16));
    return LineInfo(id: j['id'], name: j['name'], type: j['type'], color: c);
  }
}

class StationInfo {
  StationInfo({required this.id, required this.name, required this.modes});

  final String id;
  final String name;
  final List<String> modes;

  factory StationInfo.fromJson(Map<String, dynamic> j) {
    return StationInfo(
      id: j['id'],
      name: j['name'],
      modes: List<String>.from(j['modes'] as List),
    );
  }
}

class StationHomePage extends StatefulWidget {
  const StationHomePage({super.key});

  @override
  State<StationHomePage> createState() => _StationHomePageState();
}

class _StationHomePageState extends State<StationHomePage> {
  final _mqtt = SmartStationMqttClient();
  final _brokerCtrl = TextEditingController(text: '192.168.1.100');
  final _portCtrl = TextEditingController(text: '1883');

  List<LineInfo> _lines = [];
  List<StationInfo> _stations = [];
  String _selectedStation = 'metro-lac';

  final Map<String, StationTelemetry> _telemetryByStation = {};
  final Map<String, StationStatus> _statusByStation = {};
  final List<StationAlert> _alerts = [];

  String? _error;
  bool _busy = false;
  String? _brokerLabel;

  StreamSubscription<StationTelemetry>? _telSub;
  StreamSubscription<StationStatus>? _statusSub;
  StreamSubscription<StationAlert>? _alertSub;

  bool get _connected => _mqtt.isConnected;

  @override
  void initState() {
    super.initState();
    _loadSeed();
  }

  Future<void> _loadSeed() async {
    final raw = await rootBundle.loadString('assets/lines.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    setState(() {
      _lines = (data['lines'] as List).map((e) => LineInfo.fromJson(e)).toList();
      _stations = (data['stations'] as List).map((e) => StationInfo.fromJson(e)).toList();
      _seedDemoArrivals();
    });
  }

  void _seedDemoArrivals() {
    final demos = [
      ('metro-lac', 'M4', 'METRO', 'Ariana', 5, 58),
      ('metro-republique', 'M1', 'METRO', 'Ben Arous', 3, 72),
      ('bus-bab-bhar', 'L5', 'BUS', 'Lac', 8, 45),
      ('tgm-carthage', 'TGM', 'TRAIN', 'La Marsa', 6, 51),
      ('metro-ariana', 'M5', 'METRO', 'Centre-ville', 4, 63),
    ];
    for (final d in demos) {
      _telemetryByStation[d.$1] = StationTelemetry(
        stationId: d.$1,
        lineId: d.$2,
        vehicleType: d.$3,
        direction: d.$4,
        etaMin: d.$5,
        occupancyPct: d.$6,
        validators: 3,
        tempC: 24,
        humidity: 48,
        crowdLevel: 2,
      );
    }
  }

  LineInfo? _line(String id) {
    for (final l in _lines) {
      if (l.id == id) return l;
    }
    return null;
  }

  String _stationName(String id) {
    for (final s in _stations) {
      if (s.id == id) return s.name;
    }
    return id;
  }

  IconData _vehicleIcon(String type) {
    switch (type.toUpperCase()) {
      case 'METRO':
        return Icons.subway;
      case 'TRAIN':
        return Icons.train;
      case 'TRAM':
        return Icons.tram;
      default:
        return Icons.directions_bus;
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
          setState(() => _telemetryByStation[t.stationId] = t);
        }
      });

      await _statusSub?.cancel();
      _statusSub = _mqtt.statusStream.listen((s) {
        if (mounted) setState(() => _statusByStation[s.stationId] = s);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Connectez-vous au broker MQTT')),
      );
      return;
    }
    try {
      await _mqtt.sendCommand(c);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Commande : $c')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Color _occColor(int occ) {
    if (occ >= 80) return const Color(0xFFB91C1C);
    if (occ >= 60) return const Color(0xFFD97706);
    return const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    final current = _telemetryByStation[_selectedStation];
    final status = _statusByStation[_selectedStation];

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('El Jezi — Smart Station'),
          centerTitle: true,
          backgroundColor: const Color(0xFF1E40AF),
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
                tooltip: _connected ? 'Deconnecter' : 'Connecter',
                onPressed: _connected ? _disconnect : _connect,
                icon: Icon(_connected ? Icons.cloud_done : Icons.cloud_off),
              ),
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.hail), text: 'Arrivees'),
              Tab(icon: Icon(Icons.route), text: 'Lignes'),
              Tab(icon: Icon(Icons.warning_amber), text: 'Alertes'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _arrivalsTab(current, status),
            _linesTab(),
            _alertsTab(),
          ],
        ),
      ),
    );
  }

  Widget _arrivalsTab(StationTelemetry? current, StationStatus? status) {
    return ListView(
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
        _connectionBanner(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ma station', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedStation,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: _stations
                      .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedStation = v);
                  },
                ),
              ],
            ),
          ),
        ),
        if (current != null) ...[
          const SizedBox(height: 12),
          _arrivalCard(current, highlight: true),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _miniStat('Temperature', '${current.tempC.toStringAsFixed(0)} °C', Icons.thermostat)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('Validateurs', '${current.validators}', Icons.confirmation_number)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('Foule', '${current.crowdLevel}/5', Icons.groups)),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text('Toutes les stations', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ..._stations.map((s) {
          final t = _telemetryByStation[s.id];
          if (t == null) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(s.name),
                subtitle: const Text('Pas de donnees'),
              ),
            );
          }
          return _arrivalCard(t);
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _connected ? () => _cmd('REFRESH_ETA') : _connect,
                icon: const Icon(Icons.refresh),
                label: Text(_connected ? 'Rafraichir ETA' : 'Connecter MQTT'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E40AF)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _connected ? () => _cmd('STATUS') : null,
                icon: const Icon(Icons.info_outline),
                label: const Text('Status'),
              ),
            ),
          ],
        ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Mode ${status.mode} · ${status.linesCount} lignes · ${status.servicesUp} services',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _linesTab() {
    final grouped = <String, List<LineInfo>>{};
    for (final l in _lines) {
      grouped.putIfAbsent(l.type, () => []).add(l);
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Reseau transport public — Grand Tunis',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ...grouped.entries.map((e) {
          final typeLabel = switch (e.key) {
            'metro' => 'Metro leger',
            'train' => 'TGM / Train',
            'bus' => 'Bus urbain',
            _ => e.key,
          };
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(typeLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              ...e.value.map((l) => Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: l.color, child: Text(l.id, style: const TextStyle(color: Colors.white, fontSize: 11))),
                      title: Text(l.name),
                      subtitle: Text('Ligne ${l.id} · ${l.type.toUpperCase()}'),
                      trailing: Icon(_vehicleIcon(l.type)),
                    ),
                  )),
              const SizedBox(height: 8),
            ],
          );
        }),
      ],
    );
  }

  Widget _alertsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_alerts.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.notifications_none, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Aucune alerte transport', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Text(
                    _connected ? 'Surveillance active' : 'Connectez MQTT ou utilisez le mode demo',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          ..._alerts.map(
            (a) => Card(
              color: const Color(0xFFFFF7ED),
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Color(0xFFD97706)),
                title: Text(a.alert, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(_stationName(a.stationId)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _arrivalCard(StationTelemetry t, {bool highlight = false}) {
    final line = _line(t.lineId);
    final occ = t.occupancyPct;
    return Card(
      color: highlight ? const Color(0xFFEFF6FF) : null,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: line?.color ?? const Color(0xFF1E40AF),
          child: Icon(_vehicleIcon(t.vehicleType), color: Colors.white, size: 20),
        ),
        title: Text('${line?.name ?? t.lineId} → ${t.direction}'),
        subtitle: Text('${_stationName(t.stationId)} · ${t.vehicleType}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${t.etaMin} min', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('${occ}%', style: TextStyle(color: _occColor(occ), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF1E40AF)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          ],
        ),
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

  Widget _connectionBanner() {
    return Card(
      color: _connected ? const Color(0xFFEFF6FF) : null,
      child: ListTile(
        leading: Icon(
          _connected ? Icons.cloud : Icons.portable_wifi_off,
          color: _connected ? const Color(0xFF1D4ED8) : Colors.grey,
        ),
        title: Text(_connected ? 'MQTT : $_brokerLabel' : 'Mode demo (donnees locales)'),
        subtitle: Text(
          _connected
              ? '${_telemetryByStation.length} stations en direct'
              : 'Lancez le simulateur 15-smart-station puis connectez-vous',
        ),
      ),
    );
  }
}
