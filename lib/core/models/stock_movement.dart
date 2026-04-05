import 'inventory_line.dart';

/// `GET /api/v1/inventory/movements` — contrato Nest/Prisma: array en raíz, camelCase.
/// Ver `FRONTEND_INTEGRATION_CONTEXT.md` §13.8.1.
class StockMovement {
  const StockMovement({
    required this.id,
    required this.storeId,
    required this.type,
    required this.quantity,
    this.productId,
    this.opId,
    this.costAtMoment,
    this.priceAtMoment,
    this.unitCostFunctional,
    this.totalCostFunctional,
    this.referenceId,
    this.reason,
    this.createdAt,
    this.product,
  });

  final String id;
  final String storeId;
  final String type;
  final String quantity;
  final String? productId;
  final String? opId;
  final String? costAtMoment;
  final String? priceAtMoment;
  final String? unitCostFunctional;
  final String? totalCostFunctional;
  final String? referenceId;
  final String? reason;
  final DateTime? createdAt;
  final InventoryProductSummary? product;

  static StockMovement fromJson(Map<String, dynamic> json) {
    InventoryProductSummary? product;
    final productRaw = json['product'];
    if (productRaw is Map) {
      product = InventoryProductSummary.fromJson(
        Map<String, dynamic>.from(productRaw),
      );
    }

    final createdRaw = json['createdAt'];
    DateTime? createdAt;
    if (createdRaw is String) {
      createdAt = DateTime.tryParse(createdRaw);
    }

    String? nullableString(Object? v) {
      if (v == null) return null;
      return v.toString();
    }

    return StockMovement(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      type: json['type']?.toString() ?? '—',
      quantity: json['quantity']?.toString() ?? '0',
      productId: nullableString(json['productId']),
      opId: nullableString(json['opId']),
      costAtMoment: nullableString(json['costAtMoment']),
      priceAtMoment: nullableString(json['priceAtMoment']),
      unitCostFunctional: nullableString(json['unitCostFunctional']),
      totalCostFunctional: nullableString(json['totalCostFunctional']),
      referenceId: nullableString(json['referenceId']),
      reason: nullableString(json['reason']),
      createdAt: createdAt,
      product: product,
    );
  }
}
