/// Línea del ticket en construcción (P1/P2; precio según producto hasta P4/P2 FX).
class PosCartLine {
  PosCartLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.unitPrice,
    required this.currency,
    this.quantity = 1,
  });

  final String productId;
  final String name;
  final String sku;
  final String unitPrice;
  final String currency;
  int quantity;
}
