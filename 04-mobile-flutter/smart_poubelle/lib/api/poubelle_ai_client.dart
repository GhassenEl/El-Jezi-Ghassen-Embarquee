import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/poubelle_ai_engine.dart';

class PoubelleAiClient {
  PoubelleAiClient(this.baseUrl);

  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<PoubelleAiInsights> fetchInsights({required String binId}) async {
    final res = await http.get(_uri('/api/v1/ai/insights', {'bin_id': binId}));
    if (res.statusCode != 200) {
      throw StateError('API poubelle ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return PoubelleAiInsights(
      binId: data['bin_id']?.toString() ?? binId,
      fillRisk: data['fill_risk']?.toString() ?? 'unknown',
      fillTrend: data['fill_trend']?.toString() ?? 'stable',
      predictedFill24h: (data['predicted_fill_24h'] as num?)?.toInt(),
      daysUntilFull: (data['days_until_full'] as num?)?.toDouble(),
      collectionPriority: (data['collection_priority'] as num?)?.toInt() ?? 0,
      anomalies: (data['anomalies'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      recommendations: (data['recommendations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      collectNow: data['collect_now'] == true,
      source: 'cloud',
    );
  }
}
