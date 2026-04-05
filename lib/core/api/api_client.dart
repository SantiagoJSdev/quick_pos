import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_error.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  Map<String, String> _headers(String storeId, {String? requestId}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Store-Id': storeId,
      if (requestId != null && requestId.isNotEmpty) 'X-Request-Id': requestId,
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> getJson(
    String path,
    String storeId, {
    Map<String, String>? query,
    String? requestId,
  }) async {
    final res = await _client.get(
      _uri(path, query),
      headers: _headers(storeId, requestId: requestId),
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
    final res = await _client.get(
      _uri(path, query),
      headers: _headers(storeId, requestId: requestId),
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
  }) async {
    final res = await _client.post(
      _uri(path),
      headers: _headers(storeId, requestId: requestId),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeSuccess(res);
  }

  Future<Map<String, dynamic>> putJson(
    String path,
    String storeId,
    Object? body, {
    String? requestId,
  }) async {
    final res = await _client.put(
      _uri(path),
      headers: _headers(storeId, requestId: requestId),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeSuccess(res);
  }

  Future<Map<String, dynamic>> patchJson(
    String path,
    String storeId,
    Object? body, {
    String? requestId,
  }) async {
    final res = await _client.patch(
      _uri(path),
      headers: _headers(storeId, requestId: requestId),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeSuccess(res);
  }

  /// `DELETE` sin cuerpo de respuesta obligatorio; acepta 200/204 con body vacío u objeto.
  Future<void> deleteNoContent(
    String path,
    String storeId, {
    String? requestId,
  }) async {
    final res = await _client.delete(
      _uri(path),
      headers: _headers(storeId, requestId: requestId),
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
}
