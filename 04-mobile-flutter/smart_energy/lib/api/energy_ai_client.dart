import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/energy_ai_engine.dart';

class EnergyAiClient {
  EnergyAiClient(this.baseUrl);

  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<EnergyAiInsights> fetchInsights({required String siteId}) async {
    final res = await http.get(_uri('/api/v1/ai/insights', {'site_id': siteId}));
    if (res.statusCode != 200) {
      throw StateError('API energy ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return EnergyAiInsights(
      siteId: data['site_id']?.toString() ?? siteId,
      efficiencyScore: (data['efficiency_score'] as num?)?.toInt() ?? 0,
      costRisk: data['cost_risk']?.toString() ?? 'unknown',
      loadTrend: data['load_trend']?.toString() ?? 'stable',
      predictedLoad2h: (data['predicted_load_2h'] as num?)?.toDouble(),
      solarCoveragePct: (data['solar_coverage_pct'] as num?)?.toInt(),
      anomalies: (data['anomalies'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      recommendations: (data['recommendations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      ecoModeRecommended: data['eco_mode_recommended'] == true,
      source: 'cloud',
    );
  }
}
