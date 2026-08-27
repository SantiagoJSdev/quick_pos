import '../models/cash_session.dart';
import 'api_client.dart';
import 'api_error.dart';

/// `docs/CASH_SESSIONS.md` — `/cash-sessions`.
class CashSessionsApi {
  CashSessionsApi(this._client);

  final ApiClient _client;

  /// `POST /cash-sessions` — idempotente por `deviceId` OPEN.
  ///
  /// [openingCash] en **moneda funcional** (ej. USD).
  ///
  /// [clientOpenedAt] solo si el backend lo soporta (pedido en
  /// `BACKEND_CASH_SESSIONS_PEDIDO.md`). El front **no** lo envía por defecto.
  Future<CashSessionInfo> openSession(
    String storeId, {
    required String deviceId,
    String openingCash = '0.00',
    String? appVersion,
    String? clientOpenedAt,
  }) async {
    final body = <String, dynamic>{
      'deviceId': deviceId,
      'openingCash': openingCash,
      if (appVersion != null && appVersion.trim().isNotEmpty)
        'appVersion': appVersion.trim(),
      if (clientOpenedAt != null && clientOpenedAt.trim().isNotEmpty)
        'clientOpenedAt': clientOpenedAt.trim(),
    };
    final json = await _client.postJson('/cash-sessions', storeId, body);
    final session = CashSessionInfo.tryFromJson(json) ??
        CashSessionInfo.tryFromJson(
          json['session'] is Map
              ? Map<String, dynamic>.from(json['session'] as Map)
              : null,
        );
    if (session == null) {
      throw ApiError(
        statusCode: 500,
        error: 'Invalid cash session response',
        messages: ['El servidor no devolvió una sesión de caja válida.'],
      );
    }
    return session;
  }

  /// `GET /cash-sessions/current?deviceId=`
  Future<CashSessionInfo?> getCurrent(
    String storeId, {
    required String deviceId,
  }) async {
    try {
      final json = await _client.getJson(
        '/cash-sessions/current',
        storeId,
        query: {'deviceId': deviceId},
      );
      return CashSessionInfo.tryFromJson(json) ??
          CashSessionInfo.tryFromJson(
            json['session'] is Map
                ? Map<String, dynamic>.from(json['session'] as Map)
                : null,
          );
    } on ApiError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<CashSessionSummaryResponse?> getSummary(
    String storeId,
    String sessionId,
  ) async {
    final json = await _client.getJson(
      '/cash-sessions/$sessionId/summary',
      storeId,
    );
    return CashSessionSummaryResponse.tryFromJson(json);
  }

  Future<CashSessionSummaryResponse?> closeSession(
    String storeId,
    String sessionId, {
    required String closeMode,
    required String countedCash,
    List<PendingSaleCloseDeclaration> pendingSales = const [],
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'closeMode': closeMode,
      'countedCash': countedCash,
      if (pendingSales.isNotEmpty)
        'pendingSales': pendingSales.map((e) => e.toJson()).toList(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    final json = await _client.postJson(
      '/cash-sessions/$sessionId/close',
      storeId,
      body,
    );
    return CashSessionSummaryResponse.tryFromJson(json);
  }
}
