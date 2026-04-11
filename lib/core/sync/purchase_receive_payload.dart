import '../pos/sale_checkout_payload.dart';

/// Cuerpo `POST /api/v1/purchases` y objeto `payload.purchase` en `sync/push`.
///
/// Contrato: `FRONTEND_INTEGRATION_CONTEXT.md` §13.10, `SYNC_CONTRACTS.md` — `PURCHASE_RECEIVE`.
class PurchaseReceivePayload {
  PurchaseReceivePayload._();

  /// Misma forma que ventas (`fxSnapshot` en §13.10).
  static Map<String, dynamic> buildFxSnapshot({
    required String documentCurrencyCode,
    required String functionalCurrencyCode,
    required SaleFxPair? fxPair,
    String? fxSource,
  }) {
    final doc = documentCurrencyCode.trim();
    final func = functionalCurrencyCode.trim();
    final rateForSnapshot =
        SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
          functionalCode: func,
          documentCode: doc,
          pair: fxPair,
        );
    final effectiveDate =
        fxPair == null || func.toUpperCase() == doc.toUpperCase()
        ? _todayYyyyMmDd()
        : fxPair.rate.effectiveDate.trim().isEmpty
        ? _todayYyyyMmDd()
        : fxPair.rate.effectiveDate.trim();
    final ed = effectiveDate.length >= 10
        ? effectiveDate.substring(0, 10)
        : effectiveDate;
    final m = <String, dynamic>{
      'baseCurrencyCode': func,
      'quoteCurrencyCode': doc,
      'rateQuotePerBase': rateForSnapshot,
      'effectiveDate': ed,
    };
    if (fxSource != null && fxSource.isNotEmpty) {
      m['fxSource'] = fxSource;
    }
    return m;
  }

  static String _todayYyyyMmDd() {
    final n = DateTime.now().toUtc();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Body REST (sin `storeId`; va en `X-Store-Id`).
  static Map<String, dynamic> toRestBody({
    required String supplierId,
    required String documentCurrencyCode,
    required List<Map<String, dynamic>> lines,
    required Map<String, dynamic> fxSnapshot,
    String? clientPurchaseId,
    String? reference,
    String? notes,
  }) {
    final ref = reference?.trim() ?? '';
    final n = notes?.trim() ?? '';
    return <String, dynamic>{
      if (clientPurchaseId != null && clientPurchaseId.isNotEmpty)
        'id': clientPurchaseId,
      'supplierId': supplierId.trim(),
      'documentCurrencyCode': documentCurrencyCode.trim(),
      'lines': lines,
      'fxSnapshot': fxSnapshot,
      if (ref.isNotEmpty) 'reference': ref,
      if (n.isNotEmpty) 'notes': n,
    };
  }

  /// Objeto dentro de `payload.purchase` en `sync/push`.
  static Map<String, dynamic> toSyncPurchaseObject({
    required String storeId,
    required String supplierId,
    required String documentCurrencyCode,
    required List<Map<String, dynamic>> lines,
    required Map<String, dynamic> fxSnapshot,
    String? clientPurchaseId,
    String? fxSource,
    String? reference,
    String? notes,
  }) {
    final fx = Map<String, dynamic>.from(fxSnapshot);
    if (fxSource != null && fxSource.isNotEmpty) {
      fx['fxSource'] = fxSource;
    }
    final ref = reference?.trim() ?? '';
    final n = notes?.trim() ?? '';
    return <String, dynamic>{
      if (clientPurchaseId != null && clientPurchaseId.isNotEmpty)
        'id': clientPurchaseId,
      'storeId': storeId.trim(),
      'supplierId': supplierId.trim(),
      'documentCurrencyCode': documentCurrencyCode.trim(),
      'lines': lines,
      'fxSnapshot': fx,
      if (ref.isNotEmpty) 'reference': ref,
      if (n.isNotEmpty) 'notes': n,
    };
  }

  static Map<String, dynamic> line({
    required String productId,
    required String quantity,
    required String unitCost,
  }) {
    return <String, dynamic>{
      'productId': productId.trim(),
      'quantity': quantity.trim(),
      'unitCost': unitCost.trim(),
    };
  }
}
