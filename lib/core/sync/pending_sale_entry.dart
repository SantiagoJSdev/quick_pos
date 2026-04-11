/// Venta en cola para `POST /api/v1/sync/push` (`opType: SALE`).
///
/// `opId` = idempotencia de la **operación** en el batch; `sale['id']` = idempotencia de la **venta** (REST).
class PendingSaleEntry {
  const PendingSaleEntry({
    required this.opId,
    required this.storeId,
    required this.sale,
    required this.opTimestampIso,
  });

  final String opId;
  final String storeId;

  /// Objeto `payload.sale` (SYNC_CONTRACTS.md).
  final Map<String, dynamic> sale;

  /// ISO-8601 UTC para `ops[].timestamp`.
  final String opTimestampIso;

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'storeId': storeId,
    'sale': sale,
    'opTimestampIso': opTimestampIso,
  };

  static PendingSaleEntry? tryFromJson(Map<String, dynamic> json) {
    final opId = json['opId'] as String?;
    final storeId = json['storeId'] as String?;
    final sale = json['sale'];
    final ts = json['opTimestampIso'] as String?;
    if (opId == null ||
        opId.isEmpty ||
        storeId == null ||
        storeId.isEmpty ||
        ts == null ||
        ts.isEmpty ||
        sale is! Map) {
      return null;
    }
    return PendingSaleEntry(
      opId: opId,
      storeId: storeId,
      sale: Map<String, dynamic>.from(sale),
      opTimestampIso: ts,
    );
  }
}
