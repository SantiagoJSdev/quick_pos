import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_connectivity_debug.dart';
import 'ngrok_headers.dart';

/// Comprueba que la base `/api/v1` responde HTTP (p. ej. antes de enlazar tienda).
Future<bool> probeApiV1Reachable(
  String apiV1Base, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final client = http.Client();
  try {
    final base = AppConfig.normalizeApiBaseUrl(apiV1Base);
    if (base.isEmpty) return false;
    final uri = Uri.parse('$base/');
    traceApiConnectivity('Probe GET $uri');
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': 'QuickPos/1 (Flutter)',
      ...ngrokSkipBrowserWarningHeadersForApiBase(base),
    };
    final r = await client.get(uri, headers: headers).timeout(timeout);
    final ok = r.statusCode < 500;
    traceApiConnectivity(
      'Probe → HTTP ${r.statusCode} (${ok ? 'OK' : 'fallo ≥500'})',
    );
    return ok;
  } catch (e) {
    traceApiConnectivity('Probe excepción: $e');
    return false;
  } finally {
    client.close();
  }
}
