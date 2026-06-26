import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/station_ai_engine.dart';

/// Client REST station-api (IA cloud legere).
class StationAiClient {
  StationAiClient(this.baseUrl);

  final String baseUrl;

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<StationAiInsights> fetchInsights({required String stationId}) async {
    final uri = Uri.parse('$_root/api/v1/ai/insights?station=${Uri.encodeComponent(stationId)}');
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw StateError('IA station ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StationAiInsights.fromJson(data);
  }

  Future<Map<String, dynamic>> health() async {
    final uri = Uri.parse('$_root/api/v1/health');
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw StateError('Health ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
