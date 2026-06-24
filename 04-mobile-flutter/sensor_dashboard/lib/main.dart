import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

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
  final _rand = math.Random();
  final List<double> _tempHistory = [];
  final List<double> _humHistory = [];
  Timer? _timer;
  double _temp = 24.0;
  double _hum = 55.0;
  double _volt = 3.30;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      setState(() {
        final n = _tempHistory.length;
        _temp = (24 + 2 * math.sin(n / 8) + _rand.nextDouble() * 0.4).clamp(20.0, 32.0);
        _hum = (55 + 5 * math.cos(n / 10) + _rand.nextDouble()).clamp(40.0, 80.0);
        _volt = 3.30 + 0.05 * math.sin(n / 5);
        _push(_tempHistory, _temp);
        _push(_humHistory, _hum);
      });
    });
  }

  void _push(List<double> list, double value) {
    list.add(value);
    if (list.length > 40) list.removeAt(0);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — Capteurs'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _metricRow(),
          const SizedBox(height: 20),
          _chartCard('Température (°C)', _tempHistory, const Color(0xFFE11D48)),
          const SizedBox(height: 12),
          _chartCard('Humidité (%)', _humHistory, const Color(0xFF2563EB)),
          const SizedBox(height: 16),
          const Card(
            child: ListTile(
              leading: Icon(Icons.memory, color: Color(0xFF059669)),
              title: Text('Source données'),
              subtitle: Text(
                'Simulation locale — brancher BLE/série depuis ESP32 (projet 01-rtos)',
              ),
            ),
          ),
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
    final spots = data.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList();

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
              child: LineChart(
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
