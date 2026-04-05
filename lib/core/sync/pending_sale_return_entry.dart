/// Devolución de venta en cola para `sync/push` (`opType: SALE_RETURN`).
///
/// [opId] = idempotencia de la operación en el batch; `saleReturn['id']` = idempotencia del documento (REST).
class PendingSaleReturnEntry {
  const PendingSaleReturnEntry({
    required this.opId,
    required this.storeId,
    required this.saleReturn,
    required this.opTimestampIso,
  });

  final String opId;
  final String storeId;

  /// Objeto anidado en `payload.saleReturn` (`SYNC_CONTRACTS.md`).
  final Map<String, dynamic> saleReturn;

  final String opTimestampIso;

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'storeId': storeId,
        'saleReturn': saleReturn,
        'opTimestampIso': opTimestampIso,
      };

  static PendingSaleReturnEntry? tryFromJson(Map<String, dynamic> json) {
    final opId = json['opId'] as String?;
    final storeId = json['storeId'] as String?;
    final sr = json['saleReturn'];
    final ts = json['opTimestampIso'] as String?;
    if (opId == null ||
        opId.isEmpty ||
        storeId == null ||
        storeId.isEmpty ||
        ts == null ||
        ts.isEmpty ||
        sr is! Map) {
      return null;
    }
    return PendingSaleReturnEntry(
      opId: opId,
      storeId: storeId,
      saleReturn: Map<String, dynamic>.from(sr),
      opTimestampIso: ts,
    );
  }
}
