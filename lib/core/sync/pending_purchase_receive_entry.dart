/// Compra / recepción en cola para `sync/push` (`opType: PURCHASE_RECEIVE`).
///
/// [opId] = idempotencia de la **operación** en el batch; `purchase['id']` = idempotencia del documento.
class PendingPurchaseReceiveEntry {
  const PendingPurchaseReceiveEntry({
    required this.opId,
    required this.storeId,
    required this.purchase,
    required this.opTimestampIso,
  });

  final String opId;
  final String storeId;

  /// Objeto anidado en `payload.purchase` (`SYNC_CONTRACTS.md`).
  final Map<String, dynamic> purchase;

  final String opTimestampIso;

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'storeId': storeId,
    'purchase': purchase,
    'opTimestampIso': opTimestampIso,
  };

  static PendingPurchaseReceiveEntry? tryFromJson(Map<String, dynamic> json) {
    final opId = json['opId'] as String?;
    final storeId = json['storeId'] as String?;
    final p = json['purchase'];
    final ts = json['opTimestampIso'] as String?;
    if (opId == null ||
        opId.isEmpty ||
        storeId == null ||
        storeId.isEmpty ||
        ts == null ||
        ts.isEmpty ||
        p is! Map) {
      return null;
    }
    return PendingPurchaseReceiveEntry(
      opId: opId,
      storeId: storeId,
      purchase: Map<String, dynamic>.from(p),
      opTimestampIso: ts,
    );
  }
}
