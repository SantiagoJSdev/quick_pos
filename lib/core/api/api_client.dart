import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../network/ngrok_headers.dart';
import 'api_error.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
    : _client = httpClient ?? http.Client(),
      _baseUrlOverride = baseUrl;

  final http.Client _client;
  final String? _baseUrlOverride;
  static const _uuid = Uuid();

  /// Emulador + túnel ngrok suelen superar 12s en el primer round-trip; 408 en probe = agotó esto.
  static const _requestTimeout = Duration(seconds: 30);

  /// UUID v4 por petición si no se pasa uno explícito (`FRONTEND_INTEGRATION_CONTEXT.md`).
  String _effectiveRequestId(String? requestId) =>
      (requestId != null && requestId.isNotEmpty) ? requestId : _uuid.v4();

  String _effectiveBaseUrl() =>
      _baseUrlOverride ?? AppConfig.effectiveApiBaseUrl;

  Map<String, String> _headers(String storeId, {String? requestId}) {
    return {
      ...ngrokSkipBrowserWarningHeadersForApiBase(_effectiveBaseUrl()),
      'User-Agent': 'QuickPos/1 (Flutter)',
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Store-Id': storeId,
      'X-Request-Id': _effectiveRequestId(requestId),
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final configured = _effectiveBaseUrl();
    final base = configured.endsWith('/')
        ? configured.substring(0, configured.length - 1)
        : configured;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> getJson(
    String path,
    String storeId, {
    Map<String, String>? query,
    String? requestId,
  }) async {
    final res = await _withTimeout(
      _client.get(
        _uri(path, query),
        headers: _headers(storeId, requestId: requestId),
      ),
    );
    return _decodeSuccess(res);
  }

  /// Respuestas que son un **array** JSON o un objeto con lista en
  /// `data` / `items` / `results` / `lines` (ver `docs/UX_INVENTARIO_PRODUCTOS.md`).
  /// `GET /inventory/movements` (Nest): raíz = `[ ... ]` sin wrapper.
  Future<List<Map<String, dynamic>>> getJsonList(
    String path,
    String storeId, {
    Map<String, String>? query,
    String? requestId,
  }) async {
    final res = await _withTimeout(
      _client.get(
        _uri(path, query),
        headers: _headers(storeId, requestId: requestId),
      ),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return [];
      final decoded = jsonDecode(res.body);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      if (decoded is Map<String, dynamic>) {
        for (final key in ['data', 'items', 'results', 'lines']) {
          final inner = decoded[key];
          if (inner is List) {
            return inner
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        }
      }
      throw ApiError(
        statusCode: res.statusCode,
        error: 'Invalid response',
        messages: ['Expected JSON array for $path'],
      );
    }
    final parsed = ApiError.tryParse(res.statusCode, res.body);
    throw parsed ??
        ApiError(
          statusCode: res.statusCode,
          error: 'HTTP ${res.statusCode}',
          messages: [res.body],
        );
  }

  Future<Map<String, dynamic>> postJson(
    String path,
    String storeId,
    Object? body, {
    String? requestId,
    String? idempotencyKey,
  }) async {
    final headers = Map<String, String>.from(
      _headers(storeId, requestId: requestId),
    );
    final ik = idempotencyKey?.trim();
    if (ik != null && ik.isNotEmpty) {
      headers['Idempotency-Key'] = ik;
    }
    final res = await _withTimeout(
      _client.post(
        _uri(path),
        headers: headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decodeSuccess(res);
  }

  Future<Map<String, dynamic>> postMultipartFile(
    String path,
    String storeId, {
    required String fileFieldName,
    required String filePath,
    String? requestId,
  }) async {
    final req = http.MultipartRequest('POST', _uri(path));
    req.headers.addAll({
      ...ngrokSkipBrowserWarningHeadersForApiBase(_effectiveBaseUrl()),
      'Accept': 'application/json',
      'X-Store-Id': storeId,
      'X-Request-Id': _effectiveRequestId(requestId),
    });
    req.files.add(await http.MultipartFile.fromPath(fileFieldName, filePath));
    http.StreamedResponse streamed;
    try {
      streamed = await req.send().timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiError(
        statusCode: 408,
        error: 'Request Timeout',
        messages: ['Tiempo de espera agotado. Verificá conexión y backend.'],
      );
    }
    final res = await http.Response.fromStream(streamed);
    return _decodeSuccess(res);
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    String storeId,
    Object? body, {
    String? requestId,
  }) async {
    final res = await _withTimeout(
      _client.put(
        _uri(path),
        headers: _headers(storeId, requestId: requestId),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decodeSuccess(res);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    String storeId,
    Object? body, {
    String? requestId,
  }) async {
    final res = await _withTimeout(
      _client.patch(
        _uri(path),
        headers: _headers(storeId, requestId: requestId),
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return _decodeSuccess(res);
  }

  /// `DELETE` con cuerpo JSON (p. ej. soft delete que devuelve el recurso).
  Future<Map<String, dynamic>> deleteJson(
    String path,
    String storeId, {
    String? requestId,
  }) async {
    final res = await _withTimeout(
      _client.delete(
        _uri(path),
        headers: _headers(storeId, requestId: requestId),
      ),
    );
    return _decodeSuccess(res);
  }

  /// `DELETE` sin cuerpo de respuesta obligatorio; acepta 200/204 con body vacío u objeto.
  Future<void> deleteNoContent(
    String path,
    String storeId, {
    String? requestId,
  }) async {
    final res = await _withTimeout(
      _client.delete(
        _uri(path),
        headers: _headers(storeId, requestId: requestId),
      ),
    );
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    final parsed = ApiError.tryParse(res.statusCode, res.body);
    throw parsed ??
        ApiError(
          statusCode: res.statusCode,
          error: 'HTTP ${res.statusCode}',
          messages: [res.body],
        );
  }

  Map<String, dynamic> _decodeSuccess(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return {};
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw ApiError(
        statusCode: res.statusCode,
        error: 'Invalid response',
        messages: ['Expected JSON object'],
      );
    }
    final parsed = ApiError.tryParse(res.statusCode, res.body);
    throw parsed ??
        ApiError(
          statusCode: res.statusCode,
          error: 'HTTP ${res.statusCode}',
          messages: [res.body],
        );
  }

  void close() => _client.close();

  Future<http.Response> _withTimeout(Future<http.Response> request) async {
    try {
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiError(
        statusCode: 408,
        error: 'Request Timeout',
        messages: ['Tiempo de espera agotado. Verificá conexión y backend.'],
      );
    }
  }
}
