/// Proveedor en cola para `sync/push` (`SUPPLIER_CREATE` | `SUPPLIER_UPDATE` | `SUPPLIER_DEACTIVATE`).
///
/// Ver `docs/FRONTEND_INTEGRATION_CONTEXT.md` §16: `payload` enviado es `{ "supplier": supplier }`.
class PendingSupplierMutationEntry {
  const PendingSupplierMutationEntry({
    required this.opId,
    required this.storeId,
    required this.opTimestampIso,
    required this.opType,
    required this.supplier,
  });

  final String opId;
  final String storeId;

  /// ISO-8601; orden de mezcla con el resto de colas.
  final String opTimestampIso;

  /// `SUPPLIER_CREATE` | `SUPPLIER_UPDATE` | `SUPPLIER_DEACTIVATE`
  final String opType;

  /// Objeto anidado en `payload.supplier`.
  final Map<String, dynamic> supplier;

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'storeId': storeId,
    'opTimestampIso': opTimestampIso,
    'opType': opType,
    'supplier': supplier,
  };

  static PendingSupplierMutationEntry? tryFromJson(Map<String, dynamic> json) {
    final opId = json['opId'] as String?;
    final storeId = json['storeId'] as String?;
    final ts = json['opTimestampIso'] as String?;
    final opType = json['opType'] as String?;
    final s = json['supplier'];
    if (opId == null ||
        opId.isEmpty ||
        storeId == null ||
        storeId.isEmpty ||
        ts == null ||
        ts.isEmpty ||
        opType == null ||
        opType.isEmpty ||
        s is! Map) {
      return null;
    }
    return PendingSupplierMutationEntry(
      opId: opId,
      storeId: storeId,
      opTimestampIso: ts,
      opType: opType,
      supplier: Map<String, dynamic>.from(s),
    );
  }
}
