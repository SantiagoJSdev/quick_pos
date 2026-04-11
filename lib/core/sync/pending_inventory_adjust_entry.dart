/// Ajuste de stock en cola para `sync/push` (`opType: INVENTORY_ADJUST`).
///
/// [opId] coincide con el `opId` del REST / idempotencia del movimiento.
class PendingInventoryAdjustEntry {
  const PendingInventoryAdjustEntry({
    required this.opId,
    required this.storeId,
    required this.payload,
    required this.opTimestampIso,
  });

  final String opId;
  final String storeId;

  /// `{ "inventoryAdjust": { ... } }` — [InventoryAdjustPayloadBuilder.toSyncPayload].
  final Map<String, dynamic> payload;

  final String opTimestampIso;

  Map<String, dynamic> toJson() => {
    'opId': opId,
    'storeId': storeId,
    'payload': payload,
    'opTimestampIso': opTimestampIso,
  };

  static PendingInventoryAdjustEntry? tryFromJson(Map<String, dynamic> json) {
    final opId = json['opId'] as String?;
    final storeId = json['storeId'] as String?;
    final payload = json['payload'];
    final ts = json['opTimestampIso'] as String?;
    if (opId == null ||
        opId.isEmpty ||
        storeId == null ||
        storeId.isEmpty ||
        ts == null ||
        ts.isEmpty ||
        payload is! Map) {
      return null;
    }
    return PendingInventoryAdjustEntry(
      opId: opId,
      storeId: storeId,
      payload: Map<String, dynamic>.from(payload),
      opTimestampIso: ts,
    );
  }
}
