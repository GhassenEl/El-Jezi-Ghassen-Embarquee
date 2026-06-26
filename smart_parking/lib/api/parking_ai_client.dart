import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/parking_ai_engine.dart';

class ParkingAiClient {
  ParkingAiClient(this.baseUrl);

  final String baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path').replace(queryParameters: query);
  }

  Future<ParkingAiInsights> fetchInsights({required String lotId}) async {
    final res = await http.get(_uri('/api/v1/ai/insights', {'lot_id': lotId}));
    if (res.statusCode != 200) {
      throw StateError('API parking ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ParkingAiInsights(
      lotId: data['lot_id']?.toString() ?? lotId,
      occupancyRisk: data['occupancy_risk']?.toString() ?? 'unknown',
      occupancyTrend: data['occupancy_trend']?.toString() ?? 'stable',
      predictedOcc2h: (data['predicted_occ_2h'] as num?)?.toInt(),
      minutesUntilFull: (data['minutes_until_full'] as num?)?.toInt(),
      bestAlternative: data['best_alternative']?.toString(),
      anomalies: (data['anomalies'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      recommendations: (data['recommendations'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      navigateHere: data['navigate_here'] == true,
      source: 'cloud',
    );
  }
}
