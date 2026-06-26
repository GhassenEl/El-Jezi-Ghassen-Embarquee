class OccSample {
  const OccSample({required this.at, required this.occupancyPct, required this.spotsFree});

  final DateTime at;
  final int occupancyPct;
  final int spotsFree;
}

class ParkingAiInsights {
  const ParkingAiInsights({
    required this.lotId,
    required this.occupancyRisk,
    required this.occupancyTrend,
    required this.predictedOcc2h,
    required this.minutesUntilFull,
    required this.bestAlternative,
    required this.anomalies,
    required this.recommendations,
    required this.navigateHere,
    this.source = 'local',
  });

  final String lotId;
  final String occupancyRisk;
  final String occupancyTrend;
  final int? predictedOcc2h;
  final int? minutesUntilFull;
  final String? bestAlternative;
  final List<String> anomalies;
  final List<String> recommendations;
  final bool navigateHere;
  final String source;
}

class ParkingLotView {
  const ParkingLotView({
    required this.lotId,
    required this.spotsTotal,
    required this.spotsFree,
    required this.occupancyPct,
    required this.evFree,
    required this.gateOpen,
  });

  final String lotId;
  final int spotsTotal;
  final int spotsFree;
  final int occupancyPct;
  final int evFree;
  final bool gateOpen;
}

abstract final class ParkingAiEngine {
  static ParkingAiInsights analyze({
    required String lotId,
    ParkingLotView? current,
    required List<OccSample> history,
    Map<String, ParkingLotView>? allLots,
  }) {
    if (history.isEmpty && current == null) {
      return ParkingAiInsights(
        lotId: lotId,
        occupancyRisk: 'unknown',
        occupancyTrend: 'stable',
        predictedOcc2h: null,
        minutesUntilFull: null,
        bestAlternative: null,
        anomalies: const ['Pas de donnees'],
        recommendations: const ['Connectez MQTT ou mode demo'],
        navigateHere: false,
      );
    }

    final occs = history.map((s) => s.occupancyPct).toList();
    if (current != null) occs.add(current.occupancyPct);
    final currentOcc = occs.last;
    final trend = _trend(occs);
    final slope = occs.length >= 2 ? occs.last - occs[occs.length - 2] : 0;
    final predicted = (currentOcc + slope * 4).clamp(0, 100);
    int? minsFull;
    if (slope > 0 && currentOcc < 98) {
      minsFull = ((98 - currentOcc) / slope * 15).round().clamp(5, 240);
    }

    final risk = currentOcc >= 90 ? 'high' : currentOcc >= 75 ? 'medium' : 'low';
    final evFree = current?.evFree ?? 0;
    final gate = current?.gateOpen ?? true;

    final anomalies = <String>[];
    if (currentOcc >= 95) {
      anomalies.add('Parking sature $currentOcc%');
    } else if (currentOcc >= 85) {
      anomalies.add('Occupation elevee $currentOcc%');
    }
    if (evFree == 0) anomalies.add('Aucune borne EV libre');
    if (!gate) anomalies.add('Barriere fermee');

    String? bestAlt;
    if (allLots != null && currentOcc >= 80) {
      String? candidate;
      var bestOcc = currentOcc;
      for (final e in allLots.entries) {
        if (e.key == lotId) continue;
        if (e.value.occupancyPct < bestOcc - 10) {
          bestOcc = e.value.occupancyPct;
          candidate = e.key;
        }
      }
      bestAlt = candidate;
    }

    final recs = <String>[];
    final navigate = currentOcc < 75 && gate;
    if (currentOcc >= 90) {
      recs.add('Eviter ce parking');
    } else if (currentOcc >= 75) {
      recs.add('Arrivee rapide recommandee');
    }
    if (bestAlt != null) recs.add('Alternative : $bestAlt');
    if (evFree == 0) recs.add('Pas de borne EV disponible');
    if (recs.isEmpty) recs.add('Bon choix — places disponibles');

    return ParkingAiInsights(
      lotId: lotId,
      occupancyRisk: risk,
      occupancyTrend: trend,
      predictedOcc2h: predicted,
      minutesUntilFull: minsFull,
      bestAlternative: bestAlt,
      anomalies: anomalies,
      recommendations: recs,
      navigateHere: navigate,
    );
  }

  static String _trend(List<int> vals) {
    if (vals.length < 2) return 'stable';
    final d = vals.last - vals.first;
    if (d > 8) return 'hausse';
    if (d < -5) return 'baisse';
    return 'stable';
  }
}
