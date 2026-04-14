import '../pos/sale_checkout_payload.dart';

/// Cuerpo `POST /api/v1/purchases` y objeto `payload.purchase` en `sync/push`.
///
/// Contrato Quick Market (lista blanca en servidor):
/// - REST: `supplierInvoiceReference` (no usar `reference`).
/// - sync `payload.purchase`: preferido `supplierInvoiceReference`; alias `reference`
///   solo por compatibilidad (este cliente envía solo el canónico).
class PurchaseReceivePayload {
  PurchaseReceivePayload._();

  /// Límite REST (>120 →400). En sync el servidor puede truncar.
  static const int maxSupplierInvoiceReferenceLength = 120;

  /// Misma forma que ventas / sync (`fxSnapshot`).
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

  /// Une «Nº factura» y «Notas del documento» en un solo valor para
  /// [supplierInvoiceReference] (el body no incluye `notes` en lista blanca).
  static String buildSupplierInvoiceReferenceForApi({
    required String invoiceRef,
    required String documentNotes,
  }) {
    final r = invoiceRef.trim();
    final n = documentNotes.trim();
    if (r.isEmpty && n.isEmpty) return '';
    if (n.isEmpty) return r;
    if (r.isEmpty) return n;
    return '$r · $n';
  }

  /// Body REST (sin `storeId`; va en `X-Store-Id`).
  static Map<String, dynamic> toRestBody({
    required String supplierId,
    required String documentCurrencyCode,
    required List<Map<String, dynamic>> lines,
    required Map<String, dynamic> fxSnapshot,
    String? clientPurchaseId,
    String? supplierInvoiceReference,
  }) {
    final ref = supplierInvoiceReference?.trim() ?? '';
    return <String, dynamic>{
      if (clientPurchaseId != null && clientPurchaseId.isNotEmpty)
        'id': clientPurchaseId,
      'supplierId': supplierId.trim(),
      'documentCurrencyCode': documentCurrencyCode.trim(),
      'lines': lines,
      'fxSnapshot': fxSnapshot,
      if (ref.isNotEmpty) 'supplierInvoiceReference': ref,
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
    String? supplierInvoiceReference,
  }) {
    final fx = Map<String, dynamic>.from(fxSnapshot);
    if (fxSource != null && fxSource.isNotEmpty) {
      fx['fxSource'] = fxSource;
    }
    final ref = supplierInvoiceReference?.trim() ?? '';
    return <String, dynamic>{
      if (clientPurchaseId != null && clientPurchaseId.isNotEmpty)
        'id': clientPurchaseId,
      'storeId': storeId.trim(),
      'supplierId': supplierId.trim(),
      'documentCurrencyCode': documentCurrencyCode.trim(),
      'lines': lines,
      'fxSnapshot': fx,
      if (ref.isNotEmpty) 'supplierInvoiceReference': ref,
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
