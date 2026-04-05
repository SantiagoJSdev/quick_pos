/// Respuesta de `POST /api/v1/inventory/adjustments` — §13.7.
class InventoryAdjustmentResult {
  const InventoryAdjustmentResult({
    required this.status,
    this.movementId,
  });

  final String status;
  final String? movementId;

  bool get applied => status == 'applied';
  bool get skipped => status == 'skipped';

  static InventoryAdjustmentResult fromJson(Map<String, dynamic> json) {
    return InventoryAdjustmentResult(
      status: json['status']?.toString() ?? '',
      movementId: json['movementId']?.toString(),
    );
  }
}
