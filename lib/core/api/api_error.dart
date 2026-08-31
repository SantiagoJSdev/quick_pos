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

  String get userMessage => messages.isEmpty ? error : messages.join('\n');

  /// Texto para UI / soporte: incluye `requestId` del cuerpo M0 si el servidor lo devolvió.
  String get userMessageForSupport {
    final base = userMessage;
    if (requestId == null || requestId!.isEmpty) return base;
    return '$base\n(requestId: $requestId)';
  }

  /// Mensaje en español para conflictos de catálogo (SKU / código de barras duplicado).
  /// Si no parece un duplicado, devuelve [userMessageForSupport].
  String get catalogConflictMessageEs {
    final blob = '${error.toLowerCase()}\n${messages.join('\n').toLowerCase()}';
    final looksDuplicate =
        blob.contains('unique') ||
        blob.contains('duplicate') ||
        blob.contains('already exists') ||
        blob.contains('already exist') ||
        blob.contains('already registered') ||
        blob.contains('constraint failed') ||
        blob.contains('p2002') ||
        ((statusCode == 409) &&
            (blob.contains('barcode') ||
                blob.contains('sku') ||
                blob.contains('product')));
    if (!looksDuplicate) return userMessageForSupport;

    final isBarcode =
        blob.contains('barcode') ||
        blob.contains('código de barras') ||
        blob.contains('codigo de barras');
    final isSku = blob.contains('sku') && !isBarcode;
    if (isBarcode) {
      return 'Ya existe un producto con este código de barras. '
          'Usá otro código o editá el producto que ya está en el catálogo.';
    }
    if (isSku) {
      return 'Ya existe un producto con este SKU. '
          'Usá otro SKU o editá el producto existente.';
    }
    return 'Producto duplicado: ya existe uno con el mismo código de barras o SKU. '
        'Revisá el catálogo o editá el producto existente.';
  }

  /// True si el error parece stock insuficiente (venta / sync).
  bool get looksLikeInsufficientStock {
    final blob = '${error.toLowerCase()}\n${messages.join('\n').toLowerCase()}';
    const keys = <String>[
      'insufficient_stock',
      'insufficient stock',
      'stock_insufficient',
      'out of stock',
      'sin stock',
      'no hay stock',
      'not enough stock',
      'stock insuficiente',
      'inventory_insufficient',
      'qty_exceed',
      'quantity exceeds',
    ];
    for (final k in keys) {
      if (blob.contains(k)) return true;
    }
    return false;
  }

  /// Mensaje de cobro POS en español (stock, pagos, etc.).
  String get posCheckoutMessageEs {
    if (looksLikeInsufficientStock) {
      return 'Error: no hay stock suficiente para uno o más productos del ticket.';
    }
    final raw = userMessageForSupport;
    if (raw.contains('PAYMENTS_TOTAL_MISMATCH')) {
      return 'El total pagado no cuadra con el total del ticket.';
    }
    if (raw.contains('PAYMENTS_MISSING_FX_SNAPSHOT')) {
      return 'Falta la tasa (fxSnapshot) para convertir uno de los pagos.';
    }
    if (raw.contains('PAYMENTS_FX_PAIR_MISMATCH')) {
      return 'La tasa enviada no coincide con el par de monedas del ticket.';
    }
    if (raw.contains('PAYMENTS_INVALID_AMOUNT')) {
      return 'Hay un monto de pago inválido. Revisá los campos de cobro.';
    }
    return raw;
  }

  /// Mensaje en español para `POST /inventory/adjustments`.
  String get inventoryAdjustMessageEs {
    final blob =
        '${error.toUpperCase()}\n${messages.join('\n').toUpperCase()}';
    if (blob.contains('UNIT_COST_REQUIRED_FOR_ZERO_STOCK')) {
      return 'Con stock en cero tenés que indicar el costo unitario '
          '(funcional), o cargar costo en la ficha del producto.';
    }
    if (blob.contains('INVALID_UNIT_COST_FOR_IN_ADJUST')) {
      return 'Costo unitario inválido: debe ser un número mayor que 0.';
    }
    final lower = blob.toLowerCase();
    if (lower.contains('invalid unit cost') &&
        lower.contains('in adjust')) {
      return 'Costo unitario inválido para esta entrada. '
          'Con stock en cero, indicá un costo mayor que 0 o revisá el costo '
          'en catálogo.';
    }
    return userMessageForSupport;
  }

  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isServerError => statusCode >= 500 && statusCode < 600;

  /// Transporte / timeout (p. ej. sin red). Incluye mensajes en español del [ApiClient].
  bool get isLikelyTransportFailure {
    if (statusCode == 408) return true;
    final blob = '${error.toLowerCase()}\n${messages.join('\n').toLowerCase()}';
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
  String toString() => 'ApiError($statusCode, $error, requestId: $requestId)';
}
