import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Protocole BLE partagé ESP32 ↔ Flutter (voir aussi firmware 01-rtos).
abstract final class ElJeziBleUuids {
  static const deviceName = 'ElJezi-ESP32';

  static final service = Guid('4fafc201-1fb5-459e-8fcc-c5c9c331914b');
  static final command = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a8');
  static final status = Guid('beb5483e-36e1-4688-b7f5-ea07361b26a9');
}

/// Données capteurs parsées depuis la caractéristique STATUS.
class SensorSample {
  const SensorSample({required this.temp, required this.humidity, required this.voltage});

  final double temp;
  final double humidity;
  final double voltage;

  static SensorSample? tryParse(String raw) {
    final m = RegExp(
      r'T\s*=\s*([-.\d]+)\s*,\s*H\s*=\s*([-.\d]+)\s*,\s*V\s*=\s*([-.\d]+)',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return SensorSample(
      temp: double.tryParse(m.group(1)!) ?? 0,
      humidity: double.tryParse(m.group(2)!) ?? 0,
      voltage: double.tryParse(m.group(3)!) ?? 0,
    );
  }
}

/// Client BLE pour l'ESP32 El Jezi (scan, connexion, commandes, notifications).
class ElJeziBleClient {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _statusChar;

  BluetoothDevice? get device => _device;
  bool get isConnected => _device != null && _cmdChar != null;

  Stream<BluetoothConnectionState> connectionState() {
    final d = _device;
    if (d == null) return const Stream.empty();
    return d.connectionState;
  }

  /// Scan 8 s et retourne le premier appareil ElJezi-ESP32 trouvé.
  Future<BluetoothDevice?> scanForEsp32({Duration timeout = const Duration(seconds: 8)}) async {
    if (await FlutterBluePlus.isSupported == false) {
      throw StateError('Bluetooth non supporté');
    }

    final adapter = await FlutterBluePlus.adapterState.first;
    if (adapter != BluetoothAdapterState.on) {
      throw StateError('Activez le Bluetooth');
    }

    BluetoothDevice? found;
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName;
        if (name == ElJeziBleUuids.deviceName ||
            name.toLowerCase().contains('eljezi')) {
          found = r.device;
        }
      }
    });

    await FlutterBluePlus.startScan(timeout: timeout);
    await sub.cancel();
    return found;
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();
    _device = device;
    await device.connect(timeout: const Duration(seconds: 12));
    final services = await device.discoverServices();

    BluetoothCharacteristic? cmd;
    BluetoothCharacteristic? status;
    for (final s in services) {
      if (s.uuid != ElJeziBleUuids.service) continue;
      for (final c in s.characteristics) {
        if (c.uuid == ElJeziBleUuids.command) cmd = c;
        if (c.uuid == ElJeziBleUuids.status) status = c;
      }
    }

    if (cmd == null || status == null) {
      await disconnect();
      throw StateError('Service El Jezi introuvable sur cet appareil');
    }

    _cmdChar = cmd;
    _statusChar = status;
    await _statusChar!.setNotifyValue(true);
  }

  Future<void> disconnect() async {
    try {
      await _statusChar?.setNotifyValue(false);
    } catch (_) {}
    _cmdChar = null;
    _statusChar = null;
    final d = _device;
    _device = null;
    if (d != null) {
      await d.disconnect();
    }
  }

  Future<void> sendCommand(String cmd) async {
    final c = _cmdChar;
    if (c == null) throw StateError('Non connecté');
    await c.write(cmd.codeUnits, withoutResponse: true);
  }

  Stream<SensorSample> statusStream() {
    final c = _statusChar;
    if (c == null) return const Stream.empty();
    return c.lastValueStream
        .map((data) => String.fromCharCodes(data))
        .map(SensorSample.tryParse)
        .where((s) => s != null)
        .cast<SensorSample>();
  }

  Future<SensorSample?> readStatusOnce() async {
    final c = _statusChar;
    if (c == null) return null;
    final data = await c.read();
    return SensorSample.tryParse(String.fromCharCodes(data));
  }
}
