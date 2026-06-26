class LoadSample {
  const LoadSample({required this.at, required this.loadKw, required this.solarKw, required this.gridKw});

  final DateTime at;
  final double loadKw;
  final double solarKw;
  final double gridKw;
}

class EnergyAiInsights {
  const EnergyAiInsights({
    required this.siteId,
    required this.efficiencyScore,
    required this.costRisk,
    required this.loadTrend,
    required this.predictedLoad2h,
    required this.solarCoveragePct,
    required this.anomalies,
    required this.recommendations,
    required this.ecoModeRecommended,
    this.source = 'local',
  });

  final String siteId;
  final int efficiencyScore;
  final String costRisk;
  final String loadTrend;
  final double? predictedLoad2h;
  final int? solarCoveragePct;
  final List<String> anomalies;
  final List<String> recommendations;
  final bool ecoModeRecommended;
  final String source;
}

class EnergySiteView {
  const EnergySiteView({
    required this.siteId,
    required this.loadKw,
    required this.solarKw,
    required this.gridKw,
    required this.batteryPct,
    required this.costTndH,
    required this.peak,
  });

  final String siteId;
  final double loadKw;
  final double solarKw;
  final double gridKw;
  final int batteryPct;
  final double costTndH;
  final bool peak;
}

abstract final class EnergyAiEngine {
  static EnergyAiInsights analyze({
    required String siteId,
    EnergySiteView? current,
    required List<LoadSample> history,
  }) {
    if (history.isEmpty && current == null) {
      return EnergyAiInsights(
        siteId: siteId,
        efficiencyScore: 0,
        costRisk: 'unknown',
        loadTrend: 'stable',
        predictedLoad2h: null,
        solarCoveragePct: null,
        anomalies: const ['Pas de donnees'],
        recommendations: const ['Connectez MQTT ou mode demo'],
        ecoModeRecommended: false,
      );
    }

    final loads = history.map((s) => s.loadKw).toList();
    if (current != null) loads.add(current.loadKw);
    final currentLoad = loads.last;
    final trend = _trend(loads);
    final slope = loads.length >= 2 ? loads.last - loads[loads.length - 2] : 0;
    final predicted = (currentLoad + slope * 3).clamp(0, 9999).toDouble();

    final solar = current?.solarKw ?? (history.isNotEmpty ? history.last.solarKw : 0);
    final grid = current?.gridKw ?? 0;
    final batt = current?.batteryPct ?? 0;
    final cost = current?.costTndH ?? 0;
    final peak = current?.peak ?? false;

    final coverage = currentLoad > 0 ? (solar / currentLoad * 100).round().clamp(0, 100) : 0;
    final efficiency = (coverage + (batt > 50 ? 20 : 0) - (peak ? 15 : 0)).clamp(0, 100);
    final costRisk = cost > 50 || peak ? 'high' : cost > 20 ? 'medium' : 'low';

    final anomalies = <String>[];
    if (peak) anomalies.add('Pic consommation actif');
    if (currentLoad > 0 && grid > currentLoad * 0.8) {
      anomalies.add('Dependance reseau elevee');
    }
    if (batt < 25 && batt > 0) anomalies.add('Batterie faible $batt%');

    final eco = peak || costRisk == 'high' || (batt < 30 && batt > 0);
    final recs = <String>[];
    if (eco) recs.add('Activer mode ECO');
    if (coverage > 60) recs.add('Reporter charges flexibles (bon solaire)');
    if (batt < 40 && batt > 0) recs.add('Recharger batterie heures creuses');
    if (recs.isEmpty) recs.add('Profil energetique equilibre');

    return EnergyAiInsights(
      siteId: siteId,
      efficiencyScore: efficiency,
      costRisk: costRisk,
      loadTrend: trend,
      predictedLoad2h: predicted,
      solarCoveragePct: coverage,
      anomalies: anomalies,
      recommendations: recs,
      ecoModeRecommended: eco,
    );
  }

  static String _trend(List<double> vals) {
    if (vals.length < 2) return 'stable';
    final d = vals.last - vals.first;
    if (d > 15) return 'hausse';
    if (d < -10) return 'baisse';
    return 'stable';
  }
}
