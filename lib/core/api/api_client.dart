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
