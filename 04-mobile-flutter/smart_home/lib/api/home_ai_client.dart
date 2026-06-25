import 'dart:convert';

import 'package:http/http.dart' as http;

import '../ai/home_ai_engine.dart';

class HomeAiClient {
  HomeAiClient(this.baseUrl);

  final String baseUrl;

  String get _root => baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<HomeAiInsights> fetchInsights({
    required String zone,
    String mode = 'HOME',
  }) async {
    final uri = Uri.parse(
      '$_root/api/v1/ai/insights?zone=${Uri.encodeComponent(zone)}&mode=${Uri.encodeComponent(mode)}',
    );
    final res = await http.get(uri).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) {
      throw StateError('IA home ${res.statusCode}: ${res.body}');
    }
    return HomeAiInsights.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> health() async {
    final uri = Uri.parse('$_root/api/v1/health');
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) throw StateError('Health ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
