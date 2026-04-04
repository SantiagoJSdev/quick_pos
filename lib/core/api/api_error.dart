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
