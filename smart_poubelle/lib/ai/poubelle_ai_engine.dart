class FillSample {
  const FillSample({
    required this.at,
    required this.fillPct,
    required this.weightKg,
    required this.gasPpm,
  });

  final DateTime at;
  final int fillPct;
  final double weightKg;
  final int gasPpm;
}

class PoubelleAiInsights {
  const PoubelleAiInsights({
    required this.binId,
    required this.fillRisk,
    required this.fillTrend,
    required this.predictedFill24h,
    required this.daysUntilFull,
    required this.collectionPriority,
    required this.anomalies,
    required this.recommendations,
    required this.collectNow,
    this.source = 'local',
  });

  final String binId;
  final String fillRisk;
  final String fillTrend;
  final int? predictedFill24h;
  final double? daysUntilFull;
  final int collectionPriority;
  final List<String> anomalies;
  final List<String> recommendations;
  final bool collectNow;
  final String source;
}

abstract final class PoubelleAiEngine {
  static PoubelleAiInsights analyze({
    required String binId,
    PoubelleTelemetryView? current,
    required List<FillSample> history,
    Map<String, PoubelleTelemetryView>? allBins,
  }) {
    if (history.isEmpty && current == null) {
      return PoubelleAiInsights(
        binId: binId,
        fillRisk: 'unknown',
        fillTrend: 'stable',
        predictedFill24h: null,
        daysUntilFull: null,
        collectionPriority: 0,
        anomalies: const ['Pas de donnees'],
        recommendations: const ['Connectez MQTT ou mode demo'],
        collectNow: false,
      );
    }

    final fills = history.map((s) => s.fillPct).toList();
    if (current != null) fills.add(current.fillPct);
    final currentFill = fills.last;
    final trend = _fillTrend(fills);
    final slope = fills.length >= 2 ? fills.last - fills[fills.length - 2] : 0;
    final predicted = (currentFill + slope * 8).clamp(0, 100);
    double? daysUntil;
    if (slope > 0) {
      daysUntil = ((95 - currentFill) / (slope * 4)).clamp(0, 30).toDouble();
    } else if (currentFill >= 95) {
      daysUntil = 0;
    }

    final risk = currentFill >= 90 ? 'high' : currentFill >= 75 ? 'medium' : 'low';
    final priority = (currentFill + (trend == 'hausse' ? 15 : 0)).clamp(0, 100);
    final gas = current?.gasPpm ?? (history.isNotEmpty ? history.last.gasPpm : 0);
    final batt = current?.batteryPct ?? 100;
    final lid = current?.lidOpen ?? false;

    final anomalies = <String>[];
    if (currentFill >= 95) {
      anomalies.add('Poubelle pleine $currentFill%');
    } else if (currentFill >= 85) {
      anomalies.add('Remplissage eleve $currentFill%');
    }
    if (gas > 250) anomalies.add('Odeur/gaz eleve $gas ppm');
    if (batt < 25) anomalies.add('Batterie faible $batt%');
    if (lid) anomalies.add('Couvercle ouvert');

    final collectNow = currentFill >= 88 || (trend == 'hausse' && currentFill >= 80);
    final recs = <String>[];
    if (collectNow) recs.add('Planifier collecte urgente');
    if (gas > 200) recs.add('Verifier contenu organique');
    if (batt < 30) recs.add('Remplacer batterie capteur');
    if (recs.isEmpty) recs.add('Niveau normal — surveillance continue');

    return PoubelleAiInsights(
      binId: binId,
      fillRisk: risk,
      fillTrend: trend,
      predictedFill24h: predicted,
      daysUntilFull: daysUntil,
      collectionPriority: priority,
      anomalies: anomalies,
      recommendations: recs,
      collectNow: collectNow,
    );
  }

  static String _fillTrend(List<int> fills) {
    if (fills.length < 2) return 'stable';
    final d = fills.last - fills.first;
    if (d > 8) return 'hausse';
    if (d < -5) return 'baisse';
    return 'stable';
  }
}

class PoubelleTelemetryView {
  const PoubelleTelemetryView({
    required this.binId,
    required this.wasteType,
    required this.fillPct,
    required this.weightKg,
    required this.lidOpen,
    required this.gasPpm,
    required this.batteryPct,
  });

  final String binId;
  final String wasteType;
  final int fillPct;
  final double weightKg;
  final bool lidOpen;
  final int gasPpm;
  final int batteryPct;
}
