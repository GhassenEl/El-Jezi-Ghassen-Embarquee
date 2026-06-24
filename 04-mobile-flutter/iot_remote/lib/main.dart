import 'package:flutter/material.dart';

void main() => runApp(const IotRemoteApp());

/// Télécommande simple pour GPIO / LED embarquée (ESP32).
/// Mode simulation par défaut — remplacer [_sendCommand] par écriture BLE.
class IotRemoteApp extends StatelessWidget {
  const IotRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IoT Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF059669)),
        useMaterial3: true,
      ),
      home: const RemotePage(),
    );
  }
}

class RemotePage extends StatefulWidget {
  const RemotePage({super.key});

  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  bool _ledOn = false;
  bool _relayOn = false;
  int _pwm = 128;
  String _lastCmd = '—';
  bool _connected = false;

  Future<void> _sendCommand(String cmd) async {
    setState(() => _lastCmd = cmd);
    // TODO: écriture caractéristique BLE vers ESP32 (service custom)
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Commande envoyée : $cmd'), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('El Jezi — IoT Remote'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _connected ? 'Déconnecter' : 'Connecter BLE',
            onPressed: () => setState(() => _connected = !_connected),
            icon: Icon(_connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _statusCard(),
          const SizedBox(height: 16),
          _switchTile(
            title: 'LED embarquée',
            subtitle: 'GPIO 2 — ESP32',
            value: _ledOn,
            icon: Icons.lightbulb,
            onChanged: (v) {
              setState(() => _ledOn = v);
              _sendCommand(v ? 'LED_ON' : 'LED_OFF');
            },
          ),
          _switchTile(
            title: 'Relais',
            subtitle: 'Sortie digitale',
            value: _relayOn,
            icon: Icons.power,
            onChanged: (v) {
              setState(() => _relayOn = v);
              _sendCommand(v ? 'RELAY_ON' : 'RELAY_OFF');
            },
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PWM moteur / ventilateur', style: TextStyle(fontWeight: FontWeight.w700)),
                  Slider(
                    value: _pwm.toDouble(),
                    min: 0,
                    max: 255,
                    divisions: 255,
                    label: '$_pwm',
                    onChanged: (v) => setState(() => _pwm = v.round()),
                    onChangeEnd: (v) => _sendCommand('PWM_${v.round()}'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _sendCommand('STATUS'),
            icon: const Icon(Icons.refresh),
            label: const Text('Demander état capteurs'),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    return Card(
      color: _connected ? const Color(0xFFECFDF5) : null,
      child: ListTile(
        leading: Icon(
          _connected ? Icons.link : Icons.link_off,
          color: _connected ? const Color(0xFF059669) : Colors.grey,
        ),
        title: Text(_connected ? 'BLE connecté (simulation)' : 'Mode hors ligne'),
        subtitle: Text('Dernière commande : $_lastCmd'),
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      child: SwitchListTile(
        secondary: Icon(icon, color: value ? const Color(0xFFF59E0B) : Colors.grey),
        title: Text(title),
        subtitle: Text(subtitle),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}
