/// Respuesta de `POST /api/v1/inventory/losses` — `docs/KPI_CONTRATO_FRONT.md` §5.
class InventoryLossResult {
  const InventoryLossResult({
    this.ok = true,
    this.movementId,
    this.quantityAfter,
    this.costFunctional,
  });

  final bool ok;
  final String? movementId;
  final String? quantityAfter;
  final String? costFunctional;

  static InventoryLossResult fromJson(Map<String, dynamic> json) {
    return InventoryLossResult(
      ok: json['ok'] != false,
      movementId: json['movementId']?.toString() ?? json['id']?.toString(),
      quantityAfter: json['quantityAfter']?.toString() ??
          json['quantity']?.toString(),
      costFunctional: json['costFunctional']?.toString() ??
          json['lossCostFunctional']?.toString(),
    );
  }
}
