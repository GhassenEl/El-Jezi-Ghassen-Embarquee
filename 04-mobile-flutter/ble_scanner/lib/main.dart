import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() => runApp(const BleScannerApp());

class BleScannerApp extends StatelessWidget {
  const BleScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLE Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C3AED)),
        useMaterial3: true,
      ),
      home: const BleScanPage(),
    );
  }
}

class BleScanPage extends StatefulWidget {
  const BleScanPage({super.key});

  @override
  State<BleScanPage> createState() => _BleScanPageState();
}

class _BleScanPageState extends State<BleScanPage> {
  final Map<String, ScanResult> _results = {};
  StreamSubscription<List<ScanResult>>? _sub;
  bool _scanning = false;
  String? _error;

  @override
  void dispose() {
    _stopScan();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await _stopScan();
      return;
    }

    setState(() {
      _error = null;
      _results.clear();
    });

    try {
      if (await FlutterBluePlus.isSupported == false) {
        setState(() => _error = 'Bluetooth non supporté sur cet appareil.');
        return;
      }

      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        setState(() => _error = 'Activez le Bluetooth pour scanner.');
        return;
      }

      _sub = FlutterBluePlus.scanResults.listen((list) {
        setState(() {
          for (final r in list) {
            _results[r.device.remoteId.str] = r;
          }
        });
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      setState(() => _scanning = true);

      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _scanning) _stopScan();
      });
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
    await _sub?.cancel();
    _sub = null;
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final devices = _results.values.toList()
      ..sort((a, b) => (b.rssi).compareTo(a.rssi));

    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — BLE Scanner'),
        centerTitle: true,
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              backgroundColor: Colors.orange.shade100,
              actions: [
                TextButton(onPressed: () => setState(() => _error = null), child: const Text('OK')),
              ],
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Recherche ESP32, capteurs et modules embarqués à proximité.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: devices.isEmpty
                ? Center(
                    child: Text(
                      _scanning ? 'Scan en cours…' : 'Appuyez sur Scanner',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (context, index) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final r = devices[i];
                      final name = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : 'Sans nom';
                      return ListTile(
                        leading: Icon(Icons.bluetooth, color: _rssiColor(r.rssi)),
                        title: Text(name),
                        subtitle: Text(r.device.remoteId.str),
                        trailing: Text('${r.rssi} dBm'),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScan,
        icon: Icon(_scanning ? Icons.stop : Icons.bluetooth_searching),
        label: Text(_scanning ? 'Arrêter' : 'Scanner'),
      ),
    );
  }

  Color _rssiColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -80) return Colors.orange;
    return Colors.red;
  }
}
