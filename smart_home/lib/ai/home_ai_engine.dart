import '../mqtt/smart_home_mqtt_client.dart';

class TelemetrySample {
  const TelemetrySample({
    required this.at,
    required this.tempC,
    required this.humidity,
    required this.powerW,
    required this.lux,
  });

  final DateTime at;
  final double tempC;
  final double humidity;
  final int powerW;
  final int lux;
}

class HomeAiInsights {
  const HomeAiInsights({
    required this.zone,
    required this.securityRisk,
    required this.comfortScore,
    required this.energyScore,
    required this.tempTrend,
    required this.predictedTempC,
    required this.powerWAvg,
    required this.anomalies,
    required this.recommendations,
    required this.autoModeRecommended,
    required this.source,
  });

  final String zone;
  final String securityRisk;
  final int comfortScore;
  final int energyScore;
  final String tempTrend;
  final double? predictedTempC;
  final int? powerWAvg;
  final List<String> anomalies;
  final List<String> recommendations;
  final String? autoModeRecommended;
  final String source;

  factory HomeAiInsights.fromJson(Map<String, dynamic> json) {
    return HomeAiInsights(
      zone: json['zone']?.toString() ?? '',
      securityRisk: json['security_risk']?.toString() ?? 'low',
      comfortScore: (json['comfort_score'] as num?)?.toInt() ?? 0,
      energyScore: (json['energy_score'] as num?)?.toInt() ?? 0,
      tempTrend: json['temp_trend']?.toString() ?? 'stable',
      predictedTempC: (json['predicted_temp_c'] as num?)?.toDouble(),
      powerWAvg: (json['power_w_avg'] as num?)?.toInt(),
      anomalies: (json['anomalies'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      recommendations: (json['recommendations'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      autoModeRecommended: json['auto_mode_recommended']?.toString(),
      source: json['source']?.toString() ?? 'cloud',
    );
  }
}

class HomeAiEngine {
  static HomeAiInsights analyze({
    required String zone,
    required HomeTelemetry? current,
    required HomeStatus? status,
    required List<TelemetrySample> history,
    required Map<String, HomeTelemetry> allZones,
    double targetTemp = 22,
  }) {
    final anomalies = <String>[];
    final recommendations = <String>[];
    final mode = status?.mode ?? 'HOME';

    if (current == null) {
      return HomeAiInsights(
        zone: zone,
        securityRisk: 'unknown',
        comfortScore: 0,
        energyScore: 0,
        tempTrend: 'stable',
        predictedTempC: null,
        powerWAvg: null,
        anomalies: const ['Pas de telemetrie pour cette zone'],
        recommendations: const ['Connectez MQTT ou utilisez les donnees demo'],
        autoModeRecommended: null,
        source: 'local',
      );
    }

    final temps = history.map((h) => h.tempC).toList();
    if (temps.isEmpty) temps.add(current.tempC);

    final trend = _tempTrend(temps);
    final predicted = _predictTemp(temps, current.tempC);
    final security = _securityRisk(
      mode: mode,
      motion: current.motion,
      doorOpen: current.doorOpen,
      alarmOn: status?.alarmOn ?? true,
      zone: zone,
    );
    final comfort = _comfortScore(current.tempC, current.humidity, current.lux, targetTemp);
    final energy = _energyScore(current.powerW, current.lightOn, current.heatOn, mode);
    final powers = history.map((h) => h.powerW).toList();
    final powerAvg = powers.isEmpty ? current.powerW : (powers.reduce((a, b) => a + b) / powers.length).round();

    if (current.tempC > 30) anomalies.add('Temperature elevee ${current.tempC.toStringAsFixed(1)}°C');
    if (current.humidity > 75) anomalies.add('Humidite elevee ${current.humidity.round()}%');
    if (mode == 'AWAY' && current.motion) anomalies.add('Mouvement en mode AWAY');
    if (current.doorOpen) anomalies.add('Porte ouverte');
    if (mode == 'AWAY' && (current.lightOn || current.heatOn)) {
      anomalies.add('Consommation inutile en absence');
    }
    if (current.powerW > 900) anomalies.add('Pic puissance ${current.powerW} W');

    String? autoMode;
    if (security == 'high') {
      recommendations.add('Verifier immediatement — risque securite');
      autoMode = 'AWAY';
    }
    if (mode == 'AWAY' && current.lightOn) recommendations.add('Eteindre les lumieres');
    if (mode == 'AWAY' && current.heatOn) recommendations.add('Couper le chauffage');
    if (comfort < 45 && current.heatOn) recommendations.add('Ajuster la consigne temperature');
    if (current.lux < 80 && !current.lightOn && mode == 'HOME') {
      recommendations.add('Activer l\'eclairage');
    }
    if (trend == 'hausse' && current.tempC > 26) recommendations.add('Ventiler la piece');
    if (recommendations.isEmpty) recommendations.add('Maison en equilibre');

    return HomeAiInsights(
      zone: zone,
      securityRisk: security,
      comfortScore: comfort,
      energyScore: energy,
      tempTrend: trend,
      predictedTempC: predicted,
      powerWAvg: powerAvg,
      anomalies: anomalies,
      recommendations: recommendations,
      autoModeRecommended: autoMode,
      source: 'local',
    );
  }

  static String _tempTrend(List<double> temps) {
    if (temps.length < 2) return 'stable';
    final delta = temps.last - temps.first;
    if (delta > 1.5) return 'hausse';
    if (delta < -1.5) return 'baisse';
    return 'stable';
  }

  static double? _predictTemp(List<double> temps, double current) {
    if (temps.length < 2) return current;
    final slope = (temps.last - temps[temps.length - 2]).clamp(-2.0, 2.0);
    return double.parse((current + slope * 3).clamp(10.0, 35.0).toStringAsFixed(1));
  }

  static String _securityRisk({
    required String mode,
    required bool motion,
    required bool doorOpen,
    required bool alarmOn,
    required String zone,
  }) {
    if (mode == 'AWAY' && motion && doorOpen) return 'high';
    if (mode == 'AWAY' && motion) return 'high';
    if (doorOpen && (zone == 'garage' || zone == 'cuisine')) return 'medium';
    if (mode == 'AWAY' && !alarmOn) return 'medium';
    return 'low';
  }

  static int _comfortScore(double temp, double humidity, int lux, double target) {
    final tempPenalty = (temp - target).abs() * 8;
    final humPenalty = ((humidity - 50).abs() - 10).clamp(0, 40) * 0.5;
    final luxBonus = (lux >= 200 && lux <= 600) ? 5 : 0;
    return (100 - tempPenalty - humPenalty + luxBonus).round().clamp(0, 100);
  }

  static int _energyScore(int powerW, bool lightOn, bool heatOn, String mode) {
    var score = 100 - (powerW ~/ 15).clamp(0, 90);
    if (mode == 'AWAY' && (lightOn || heatOn)) score -= 25;
    if (heatOn && powerW > 500) score -= 15;
    return score.clamp(0, 100);
  }
}
