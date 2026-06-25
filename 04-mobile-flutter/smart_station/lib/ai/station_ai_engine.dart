import '../mqtt/smart_station_mqtt_client.dart';

/// Echantillon historique pour l'analyse IA locale.
class TelemetrySample {
  const TelemetrySample({
    required this.at,
    required this.etaMin,
    required this.occupancyPct,
    required this.crowdLevel,
    required this.busDelayMin,
  });

  final DateTime at;
  final int etaMin;
  final int occupancyPct;
  final int crowdLevel;
  final int busDelayMin;
}

/// Resultats IA transport public — analyse locale sans cloud.
class StationAiInsights {
  const StationAiInsights({
    required this.stationId,
    required this.delayRisk,
    required this.comfortScore,
    required this.serviceScore,
    required this.etaTrend,
    required this.predictedEtaMin,
    required this.bestAlternativeStation,
    required this.anomalies,
    required this.recommendations,
    required this.leaveNowRecommended,
    required this.source,
  });

  final String stationId;
  final String delayRisk;
  final int comfortScore;
  final int serviceScore;
  final String etaTrend;
  final int? predictedEtaMin;
  final String? bestAlternativeStation;
  final List<String> anomalies;
  final List<String> recommendations;
  final bool leaveNowRecommended;
  final String source;

  factory StationAiInsights.fromJson(Map<String, dynamic> json) {
    return StationAiInsights(
      stationId: json['station_id']?.toString() ?? '',
      delayRisk: json['delay_risk']?.toString() ?? 'low',
      comfortScore: (json['comfort_score'] as num?)?.toInt() ?? 0,
      serviceScore: (json['service_score'] as num?)?.toInt() ?? 0,
      etaTrend: json['eta_trend']?.toString() ?? 'stable',
      predictedEtaMin: (json['predicted_eta_min'] as num?)?.toInt(),
      bestAlternativeStation: json['best_alternative_station']?.toString(),
      anomalies: (json['anomalies'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      recommendations: (json['recommendations'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      leaveNowRecommended: json['leave_now_recommended'] == true,
      source: json['source']?.toString() ?? 'cloud',
    );
  }
}

class StationAiEngine {
  /// Analyse une station a partir de l'historique et du snapshot reseau.
  static StationAiInsights analyze({
    required String stationId,
    required StationTelemetry? current,
    required List<TelemetrySample> history,
    required Map<String, StationTelemetry> allStations,
  }) {
    final anomalies = <String>[];
    final recommendations = <String>[];

    if (current == null) {
      return StationAiInsights(
        stationId: stationId,
        delayRisk: 'unknown',
        comfortScore: 0,
        serviceScore: 0,
        etaTrend: 'stable',
        predictedEtaMin: null,
        bestAlternativeStation: null,
        anomalies: const ['Pas de telemetrie pour cette station'],
        recommendations: const ['Connectez MQTT ou attendez les donnees demo'],
        leaveNowRecommended: false,
        source: 'local',
      );
    }

    final etas = history.map((h) => h.etaMin.toDouble()).toList();
    if (etas.isEmpty) etas.add(current.etaMin.toDouble());

    final etaTrend = _etaTrend(etas);
    final predicted = _predictEta(etas, current.etaMin);
    final delayRisk = _delayRisk(current, etaTrend, predicted);

    final comfort = (100 - current.occupancyPct - current.crowdLevel * 8).clamp(0, 100);
    final service = (comfort + (current.validators * 5)).clamp(0, 100).toInt();

    if (current.occupancyPct > 85) {
      anomalies.add('Affluence critique ${current.occupancyPct}%');
    }
    if (current.etaMin > 12) {
      anomalies.add('Retard important ETA ${current.etaMin} min');
    }
    if (etas.length >= 3 && etas.last - etas[etas.length - 2] > 4) {
      anomalies.add('Hausse brutale du temps d\'attente');
    }
    if (current.crowdLevel >= 4) {
      anomalies.add('Quai tres charge (${current.crowdLevel}/5)');
    }

    final bestAlt = _bestAlternative(stationId, current, allStations);

    if (delayRisk == 'high') {
      recommendations.add('Privilegier une ligne alternative ou partir plus tot');
    }
    if (comfort < 40) {
      recommendations.add('Attendre le prochain passage (affluence elevee)');
    }
    if (bestAlt != null && bestAlt != stationId) {
      recommendations.add('Station alternative moins chargee : $bestAlt');
    }
    if (current.etaMin <= 4 && comfort >= 50) {
      recommendations.add('Bon moment pour monter — confort acceptable');
    }
    if (recommendations.isEmpty) {
      recommendations.add('Trafic normal — suivez l\'affichage temps reel');
    }

    final leaveNow = current.etaMin <= 5 && comfort >= 45 && delayRisk != 'high';

    return StationAiInsights(
      stationId: stationId,
      delayRisk: delayRisk,
      comfortScore: comfort,
      serviceScore: service,
      etaTrend: etaTrend,
      predictedEtaMin: predicted,
      bestAlternativeStation: bestAlt,
      anomalies: anomalies,
      recommendations: recommendations,
      leaveNowRecommended: leaveNow,
      source: 'local',
    );
  }

  static String _etaTrend(List<double> etas) {
    if (etas.length < 2) return 'stable';
    final delta = etas.last - etas.first;
    if (delta > 3) return 'hausse';
    if (delta < -2) return 'baisse';
    return 'stable';
  }

  static int? _predictEta(List<double> etas, int current) {
    if (etas.length < 2) return current;
    final slope = (etas.last - etas[etas.length - 2]).clamp(-5.0, 5.0);
    return (current + slope * 2).round().clamp(1, 30);
  }

  static String _delayRisk(StationTelemetry t, String trend, int? predicted) {
    if (t.etaMin > 15 || (predicted != null && predicted > 18)) return 'high';
    if (t.etaMin > 8 || trend == 'hausse') return 'medium';
    return 'low';
  }

  static String? _bestAlternative(
    String stationId,
    StationTelemetry current,
    Map<String, StationTelemetry> all,
  ) {
    String? best;
    var bestScore = current.occupancyPct + current.crowdLevel * 10;
    for (final e in all.entries) {
      if (e.key == stationId) continue;
      if (e.value.vehicleType != current.vehicleType) continue;
      final score = e.value.occupancyPct + e.value.crowdLevel * 10;
      if (score < bestScore - 15) {
        bestScore = score;
        best = e.key;
      }
    }
    return best;
  }
}
