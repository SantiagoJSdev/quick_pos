import '../pos/sale_checkout_payload.dart';

/// Cuerpos `POST /sale-returns` y `payload.saleReturn` en sync (`SYNC_CONTRACTS.md`).
class SaleReturnPayload {
  SaleReturnPayload._();

  static const String fxPolicyInherit = 'INHERIT_ORIGINAL_SALE';
  static const String fxPolicySpot = 'SPOT_ON_RETURN';

  static Map<String, dynamic> buildFxSnapshot({
    required String functionalCurrencyCode,
    required String documentCurrencyCode,
    required SaleFxPair? fxPair,
    String? fxSource,
  }) {
    final func = functionalCurrencyCode.trim();
    final doc = documentCurrencyCode.trim();
    final rate = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: func,
      documentCode: doc,
      pair: fxPair,
    );
    var eff = fxPair?.rate.effectiveDate ?? '';
    if (eff.isEmpty) {
      final n = DateTime.now().toUtc();
      eff =
          '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    }
    final snap = <String, dynamic>{
      'baseCurrencyCode': func,
      'quoteCurrencyCode': doc,
      'rateQuotePerBase': rate,
      'effectiveDate': eff,
    };
    if (fxSource != null && fxSource.isNotEmpty) {
      snap['fxSource'] = fxSource;
    }
    return snap;
  }

  /// REST: sin `storeId` (va en cabecera).
  static Map<String, dynamic> toRestBody({
    required String originalSaleId,
    required List<Map<String, dynamic>> lines,
    String? clientReturnId,
    required String fxPolicy,
    Map<String, dynamic>? fxSnapshot,
  }) {
    final body = <String, dynamic>{
      'originalSaleId': originalSaleId.trim(),
      'lines': lines,
    };
    if (clientReturnId != null && clientReturnId.isNotEmpty) {
      body['id'] = clientReturnId;
    }
    if (fxPolicy == fxPolicySpot) {
      body['fxPolicy'] = fxPolicySpot;
      if (fxSnapshot != null) body['fxSnapshot'] = fxSnapshot;
    }
    return body;
  }

  /// Objeto dentro de `payload.saleReturn` para `sync/push`.
  static Map<String, dynamic> toSyncSaleReturnObject({
    required String storeId,
    required String originalSaleId,
    required List<Map<String, dynamic>> lines,
    String? clientReturnId,
    required String fxPolicy,
    Map<String, dynamic>? fxSnapshot,
    String? fxSourceOffline,
  }) {
    final sr = <String, dynamic>{
      'storeId': storeId.trim(),
      'originalSaleId': originalSaleId.trim(),
      'lines': lines,
    };
    if (clientReturnId != null && clientReturnId.isNotEmpty) {
      sr['id'] = clientReturnId;
    }
    if (fxPolicy == fxPolicySpot) {
      sr['fxPolicy'] = fxPolicySpot;
      if (fxSnapshot != null) {
        final fx = Map<String, dynamic>.from(fxSnapshot);
        if (fxSourceOffline != null && fxSourceOffline.isNotEmpty) {
          fx['fxSource'] = fxSourceOffline;
        }
        sr['fxSnapshot'] = fx;
      }
    }
    return sr;
  }

  static Map<String, dynamic> lineRow({
    required String saleLineId,
    required String quantity,
  }) {
    return {'saleLineId': saleLineId.trim(), 'quantity': quantity.trim()};
  }
}
