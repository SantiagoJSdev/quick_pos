/// Construye el body REST y el `payload` de sync para un ajuste de inventario.
///
/// Contratos: `FRONTEND_INTEGRATION_CONTEXT.md` §13.7 (REST),
/// `SYNC_CONTRACTS.md` — `INVENTORY_ADJUST` (payload con `inventoryAdjust`).
///
/// El **`opId`** va en el body REST; en `sync/push` va en la **operación** del
/// batch, no dentro de [toSyncPayload].
class InventoryAdjustPayloadBuilder {
  InventoryAdjustPayloadBuilder({
    required this.productId,
    required this.type,
    required this.quantity,
    required this.reason,
    this.unitCostFunctional,
  });

  final String productId;
  final String type;
  final String quantity;
  final String reason;
  final String? unitCostFunctional;

  /// Tras validar el formulario B3 (cantidad, motivo, tipo, costo opcional).
  factory InventoryAdjustPayloadBuilder.fromForm({
    required String productId,
    required String type,
    required String quantity,
    required String reason,
    String? unitCostFunctional,
  }) {
    final c = unitCostFunctional?.trim();
    return InventoryAdjustPayloadBuilder(
      productId: productId.trim(),
      type: type.trim(),
      quantity: quantity.trim(),
      reason: reason.trim(),
      unitCostFunctional: (c == null || c.isEmpty) ? null : c,
    );
  }

  /// `POST /api/v1/inventory/adjustments`
  Map<String, dynamic> toRestBody({required String opId}) {
    final m = <String, dynamic>{
      'productId': productId,
      'type': type,
      'quantity': quantity,
      'reason': reason,
      'opId': opId,
    };
    if (unitCostFunctional != null && unitCostFunctional!.isNotEmpty) {
      m['unitCostFunctional'] = unitCostFunctional;
    }
    return m;
  }

  /// Campo `payload` de una op `INVENTORY_ADJUST` en `sync/push` (sin `opId`).
  Map<String, dynamic> toSyncPayload() {
    final inner = <String, dynamic>{
      'productId': productId,
      'type': type,
      'quantity': quantity,
      'reason': reason,
    };
    if (unitCostFunctional != null && unitCostFunctional!.isNotEmpty) {
      inner['unitCostFunctional'] = unitCostFunctional;
    }
    return <String, dynamic>{'inventoryAdjust': inner};
  }
}
