import '../models/purchase.dart';
import '../models/purchase_void.dart';
import 'api_client.dart';
import 'api_error.dart';

class PurchasesApi {
  PurchasesApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/purchases` — recepción + pago (PAID/CREDIT/PARTIAL).
  Future<Map<String, dynamic>> createPurchase(
    String storeId,
    Map<String, dynamic> body,
  ) {
    return _client.postJson('/purchases', storeId, body);
  }

  /// `GET /api/v1/purchases/:id` — detalle (+ lines / payments).
  Future<PurchaseDetail> getPurchase(String storeId, String purchaseId) async {
    final json = await _client.getJson('/purchases/$purchaseId', storeId);
    final detail = PurchaseDetail.tryFromJson(json);
    if (detail == null) {
      throw StateError('Respuesta de compra inválida');
    }
    return detail;
  }

  /// `GET /api/v1/purchases` — listado (filtros opcionales).
  /// Por defecto el backend excluye `status=VOID`.
  Future<PurchaseListPage> listPurchases(
    String storeId, {
    String? supplierId,
    String? paymentStatus,
    String? status,
    bool? includeVoided,
    String? cursor,
    int limit = 50,
  }) async {
    final query = <String, String>{
      'limit': '$limit',
      if (supplierId != null && supplierId.isNotEmpty) 'supplierId': supplierId,
      if (paymentStatus != null && paymentStatus.isNotEmpty)
        'paymentStatus': paymentStatus,
      if (status != null && status.isNotEmpty) 'status': status,
      if (includeVoided == true) 'includeVoided': 'true',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    try {
      final json = await _client.getJson('/purchases', storeId, query: query);
      final page = PurchaseListPage.fromJson(json);
      if (page.items.isNotEmpty ||
          json.containsKey('items') ||
          json.containsKey('nextCursor') ||
          json.containsKey('meta')) {
        return page;
      }
    } on ApiError {
      // respuesta array u otro shape → getJsonList
    }
    final list = await _client.getJsonList(
      '/purchases',
      storeId,
      query: query,
    );
    return PurchaseListPage.fromList(list);
  }

  /// `GET /api/v1/purchases/payables` — deuda agrupada por proveedor.
  Future<List<PayableRow>> listPayables(String storeId) async {
    try {
      final json = await _client.getJson('/purchases/payables', storeId);
      final raw =
          json['items'] ?? json['data'] ?? json['results'] ?? json['payables'];
      if (raw is List) {
        return _mapPayables(raw);
      }
    } on ApiError {
      // fallback array
    }
    final list = await _client.getJsonList('/purchases/payables', storeId);
    return _mapPayables(list);
  }

  List<PayableRow> _mapPayables(List<dynamic> raw) {
    final out = <PayableRow>[];
    for (final e in raw) {
      if (e is Map) {
        final row = PayableRow.tryFromJson(Map<String, dynamic>.from(e));
        if (row != null) out.add(row);
      }
    }
    return out;
  }

  /// `POST /api/v1/purchases/:id/payments` — abono.
  Future<Map<String, dynamic>> createPayment(
    String storeId,
    String purchaseId,
    Map<String, dynamic> body,
  ) {
    return _client.postJson('/purchases/$purchaseId/payments', storeId, body);
  }

  /// `POST /purchases/:id/void-preview` — evalúa sin mutar (`docs/PURCHASES.md`).
  Future<PurchaseVoidPreview> previewVoidPurchase(
    String storeId,
    String purchaseId,
  ) async {
    final json = await _client.postJson(
      '/purchases/$purchaseId/void-preview',
      storeId,
      <String, dynamic>{},
    );
    final preview = PurchaseVoidPreview.tryFromJson(
      json,
      fallbackPurchaseId: purchaseId,
    );
    if (preview == null) {
      throw StateError('Respuesta void-preview inválida');
    }
    return preview;
  }

  /// `POST /purchases/:id/void` — soft void online-only (`docs/PURCHASES.md`).
  Future<PurchaseVoidPreview> voidPurchase(
    String storeId,
    String purchaseId,
    PurchaseVoidRequest request,
  ) async {
    final json = await _client.postJson(
      '/purchases/$purchaseId/void',
      storeId,
      request.toJson(),
      idempotencyKey: request.opId,
    );
    final result = PurchaseVoidPreview.tryFromJson(
      json,
      fallbackPurchaseId: purchaseId,
    );
    if (result == null) {
      // Respuesta mínima: compra con status VOID.
      final status = json['status']?.toString().toUpperCase();
      if (status == 'VOID' || json['voidedAt'] != null) {
        return PurchaseVoidPreview(
          purchaseId: purchaseId,
          canVoid: false,
          blockers: const ['ALREADY_VOID'],
          voidedAt: json['voidedAt']?.toString(),
          voidMode: json['voidMode']?.toString(),
        );
      }
      throw StateError('Respuesta void inválida');
    }
    return result;
  }
}
