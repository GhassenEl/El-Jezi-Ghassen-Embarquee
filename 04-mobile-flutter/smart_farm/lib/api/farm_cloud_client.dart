import 'dart:convert';

import 'package:http/http.dart' as http;

class FarmAiInsights {
  const FarmAiInsights({
    required this.zone,
    required this.riskLevel,
    required this.healthScore,
    required this.soilTrend,
    required this.predictedSoil6h,
    required this.hoursUntilDry,
    required this.irrigationScore,
    required this.anomalies,
    required this.recommendations,
    required this.suggestedThreshold,
    required this.autoIrrigateRecommended,
  });

  final String zone;
  final String riskLevel;
  final int healthScore;
  final String soilTrend;
  final double? predictedSoil6h;
  final double? hoursUntilDry;
  final int irrigationScore;
  final List<String> anomalies;
  final List<String> recommendations;
  final int suggestedThreshold;
  final bool autoIrrigateRecommended;

  factory FarmAiInsights.fromJson(Map<String, dynamic> json) {
    return FarmAiInsights(
      zone: json['zone']?.toString() ?? '—',
      riskLevel: json['risk_level']?.toString() ?? 'low',
      healthScore: (json['health_score'] as num?)?.toInt() ?? 0,
      soilTrend: json['soil_trend']?.toString() ?? 'stable',
      predictedSoil6h: (json['predicted_soil_6h'] as num?)?.toDouble(),
      hoursUntilDry: (json['hours_until_dry'] as num?)?.toDouble(),
      irrigationScore: (json['irrigation_score'] as num?)?.toInt() ?? 0,
      anomalies: (json['anomalies'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      recommendations: (json['recommendations'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      suggestedThreshold: (json['suggested_threshold'] as num?)?.toInt() ?? 30,
      autoIrrigateRecommended: json['auto_irrigate_recommended'] == true,
    );
  }
}

/// Client REST cloud-api Smart Farm (IA).
class FarmCloudClient {
  FarmCloudClient(this.baseUrl);

  final String baseUrl;

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<FarmAiInsights> fetchInsights({int soilThreshold = 30}) async {
    final uri = Uri.parse('$_root/api/v1/ai/insights?soil_threshold=$soilThreshold');
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw StateError('IA cloud ${res.statusCode}: ${res.body}');
    }
    return FarmAiInsights.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<bool> autoIrrigate({bool confirm = true}) async {
    final uri = Uri.parse('$_root/api/v1/ai/auto-irrigate');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'confirm': confirm}),
        )
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return false;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['executed'] == true;
  }
}
