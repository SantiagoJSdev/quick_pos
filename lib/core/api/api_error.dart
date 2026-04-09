import 'dart:convert';

/// Cuerpo de error M0: `{ statusCode, error, message[], requestId }`.
class ApiError implements Exception {
  ApiError({
    required this.statusCode,
    required this.error,
    required this.messages,
    this.requestId,
  });

  final int statusCode;
  final String error;
  final List<String> messages;
  final String? requestId;

  String get userMessage =>
      messages.isEmpty ? error : messages.join('\n');

  /// Texto para UI / soporte: incluye `requestId` del cuerpo M0 si el servidor lo devolvió.
  String get userMessageForSupport {
    final base = userMessage;
    if (requestId == null || requestId!.isEmpty) return base;
    return '$base\n(requestId: $requestId)';
  }

  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500 && statusCode < 600;

  /// Transporte / timeout (p. ej. sin red). Incluye mensajes en español del [ApiClient].
  bool get isLikelyTransportFailure {
    if (statusCode == 408) return true;
    final blob =
        '${error.toLowerCase()}\n${messages.join('\n').toLowerCase()}';
    const keys = <String>[
      'timeout',
      'agotado',
      'espera',
      'connection',
      'conexión',
      'conexion',
      'socket',
      'network',
      'host lookup',
      'failed host',
      'clientexception',
      'socketexception',
      'handshake',
    ];
    for (final k in keys) {
      if (blob.contains(k)) return true;
    }
    return false;
  }

  /// Errores que conviene reintentar automáticamente en sync.
  bool get isRetryableSyncFailure {
    return statusCode == 408 || statusCode == 429 || isServerError;
  }

  /// Errores de negocio/validación que requieren revisión manual.
  bool get isManualReviewSyncFailure {
    return isClientError && !isRetryableSyncFailure;
  }

  static ApiError? tryParse(int httpStatus, String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final raw = map['message'];
      final List<String> messages;
      if (raw is List) {
        messages = raw.map((e) => e.toString()).toList();
      } else if (raw != null) {
        messages = [raw.toString()];
      } else {
        messages = [];
      }
      return ApiError(
        statusCode: (map['statusCode'] as num?)?.toInt() ?? httpStatus,
        error: map['error'] as String? ?? 'Error',
        messages: messages,
        requestId: map['requestId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'ApiError($statusCode, $error, requestId: $requestId)';
}
