import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble/eljezi_ble_client.dart';

void main() => runApp(const SensorDashboardApp());

class SensorDashboardApp extends StatelessWidget {
  const SensorDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Capteurs Embarqués',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _ble = ElJeziBleClient();
  final _rand = math.Random();
  final List<double> _tempHistory = [];
  final List<double> _humHistory = [];
  final List<double> _voltHistory = [];

  Timer? _simTimer;
  StreamSubscription<SensorSample>? _bleSub;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  double _temp = 24.0;
  double _hum = 55.0;
  double _volt = 3.30;
  bool _bleMode = false;
  bool _busy = false;
  String? _error;
  String? _deviceLabel;

  @override
  void initState() {
    super.initState();
    _startSimulation();
  }

  void _startSimulation() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (_bleMode) return;
      setState(() {
        final n = _tempHistory.length;
        _temp = (24 + 2 * math.sin(n / 8) + _rand.nextDouble() * 0.4).clamp(20.0, 32.0);
        _hum = (55 + 5 * math.cos(n / 10) + _rand.nextDouble()).clamp(40.0, 80.0);
        _volt = 3.30 + 0.05 * math.sin(n / 5);
        _applySample(_temp, _hum, _volt);
      });
    });
  }

  void _applySample(double temp, double hum, double volt) {
    _temp = temp;
    _hum = hum;
    _volt = volt;
    _push(_tempHistory, temp);
    _push(_humHistory, hum);
    _push(_voltHistory, volt);
  }

  void _push(List<double> list, double value) {
    list.add(value);
    if (list.length > 40) list.removeAt(0);
  }

  Future<void> _connectBle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await _ble.scanForEsp32();
      if (device == null) {
        setState(() => _error = 'ESP32 « ${ElJeziBleUuids.deviceName} » introuvable.');
        return;
      }
      await _ble.connect(device);
      _deviceLabel = device.platformName.isNotEmpty ? device.platformName : ElJeziBleUuids.deviceName;

      _simTimer?.cancel();
      _bleMode = true;
      _tempHistory.clear();
      _humHistory.clear();
      _voltHistory.clear();

      await _bleSub?.cancel();
      _bleSub = _ble.statusStream().listen((s) {
        if (!mounted) return;
        setState(() => _applySample(s.temp, s.humidity, s.voltage));
      });

      await _connSub?.cancel();
      _connSub = _ble.connectionState().listen((state) {
        if (state == BluetoothConnectionState.disconnected && mounted) {
          setState(_onBleLost);
        }
      });

      await _ble.sendCommand('STATUS');
      final initial = await _ble.readStatusOnce();
      if (mounted && initial != null) {
        setState(() => _applySample(initial.temp, initial.humidity, initial.voltage));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onBleLost() {
    _bleMode = false;
    _deviceLabel = null;
    _bleSub?.cancel();
    _connSub?.cancel();
    _startSimulation();
  }

  Future<void> _disconnectBle() async {
    await _bleSub?.cancel();
    await _connSub?.cancel();
    await _ble.disconnect();
    if (mounted) {
      setState(_onBleLost);
    }
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _bleSub?.cancel();
    _connSub?.cancel();
    _ble.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — Capteurs'),
        centerTitle: true,
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              tooltip: _bleMode ? 'Déconnecter BLE' : 'Connecter ESP32',
              onPressed: _bleMode ? _disconnectBle : _connectBle,
              icon: Icon(_bleMode ? Icons.bluetooth_connected : Icons.bluetooth_searching),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Card(
              color: const Color(0xFFFEF2F2),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
                title: Text(_error!, style: const TextStyle(fontSize: 13)),
              ),
            ),
          _metricRow(),
          const SizedBox(height: 20),
          _chartCard('Température (°C)', _tempHistory, const Color(0xFFE11D48)),
          const SizedBox(height: 12),
          _chartCard('Humidité (%)', _humHistory, const Color(0xFF2563EB)),
          const SizedBox(height: 12),
          _chartCard('Tension (V)', _voltHistory, const Color(0xFF059669)),
          const SizedBox(height: 16),
          Card(
            color: _bleMode ? const Color(0xFFECFDF5) : null,
            child: ListTile(
              leading: Icon(
                _bleMode ? Icons.bluetooth_connected : Icons.memory,
                color: _bleMode ? const Color(0xFF059669) : const Color(0xFF64748B),
              ),
              title: Text(_bleMode ? 'Source : BLE $_deviceLabel' : 'Source : simulation locale'),
              subtitle: Text(
                _bleMode
                    ? 'Données live depuis l\'ESP32 (notifications STATUS)'
                    : 'Appuyez sur l\'icône BLE ou le bouton ci-dessous pour l\'ESP32',
              ),
            ),
          ),
          if (!_bleMode) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _connectBle,
              icon: const Icon(Icons.bluetooth),
              label: const Text('Connecter ESP32 en BLE'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricRow() {
    return Row(
      children: [
        Expanded(child: _kpi('T°', '${_temp.toStringAsFixed(1)} °C', Icons.thermostat)),
        const SizedBox(width: 8),
        Expanded(child: _kpi('H', '${_hum.toStringAsFixed(0)} %', Icons.water_drop)),
        const SizedBox(width: 8),
        Expanded(child: _kpi('V', '${_volt.toStringAsFixed(2)} V', Icons.bolt)),
      ],
    );
  }

  Widget _kpi(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(value, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(String title, List<double> data, Color color) {
    final spots = data.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: spots.isEmpty
                  ? const Center(child: Text('En attente de données…', style: TextStyle(color: Colors.grey)))
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: color,
                            barWidth: 3,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: color.withValues(alpha: 0.15),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
