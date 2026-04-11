import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_connectivity_debug.dart';
import 'ngrok_headers.dart';

const kBackendUrlResolver =
    'https://api-url-get.vercel.app/api/backend-base-url';

class ResolverResponse {
  ResolverResponse({required this.baseUrl, this.updatedAt});

  final String baseUrl;
  final DateTime? updatedAt;

  factory ResolverResponse.fromJson(Map<String, dynamic> j) {
    final u = (j['baseUrl'] as String?)?.trim() ?? '';
    final iso = j['updatedAt'] as String?;
    return ResolverResponse(
      baseUrl: u.replaceAll(RegExp(r'/+$'), ''),
      updatedAt: iso != null ? DateTime.tryParse(iso) : null,
    );
  }
}

/// [origin] sin path final (ej. `https://xxx.ngrok-free.dev`).
String apiV1BaseFromOrigin(String origin) {
  final o = origin.trim().replaceAll(RegExp(r'/+$'), '');
  if (o.isEmpty) return '';
  return '$o/api/v1';
}

class BackendOriginResolver {
  BackendOriginResolver({http.Client? client}) : _client = client;

  final http.Client? _client;

  /// `null` = red, timeout, JSON inválido o status ≠ 200.
  Future<ResolverResponse?> fetchFromVercel({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final c = _client ?? http.Client();
    final own = _client == null;
    try {
      traceApiConnectivity('Vercel resolver GET $kBackendUrlResolver');
      final r = await c
          .get(
            Uri.parse(kBackendUrlResolver),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(timeout);
      if (r.statusCode != 200) {
        traceApiConnectivity(
          'Vercel resolver HTTP ${r.statusCode} (esperado 200)',
        );
        return null;
      }
      final decoded = jsonDecode(r.body);
      if (decoded is! Map<String, dynamic>) {
        traceApiConnectivity('Vercel resolver: JSON no es objeto');
        return null;
      }
      final parsed = ResolverResponse.fromJson(decoded);
      if (parsed.baseUrl.isEmpty) {
        traceApiConnectivity('Vercel resolver: baseUrl vacío');
        return null;
      }
      traceApiConnectivity('Vercel OK → origin=${parsed.baseUrl}');
      return parsed;
    } catch (e) {
      traceApiConnectivity('Vercel resolver excepción: $e');
      return null;
    } finally {
      if (own) c.close();
    }
  }

  void close() => _client?.close();
}

/// Comprueba que el host responde HTTP (p. ej. antes de enlazar tienda).
Future<bool> probeApiV1Reachable(
  String apiV1Base, {
  Duration timeout = const Duration(seconds: 25),
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
