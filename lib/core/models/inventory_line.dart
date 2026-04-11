/// Resumen de producto embebido en línea de inventario (`GET /inventory`).
class InventoryProductSummary {
  const InventoryProductSummary({
    required this.id,
    this.sku,
    this.name,
    this.barcode,
  });

  final String id;
  final String? sku;
  final String? name;
  final String? barcode;

  static InventoryProductSummary? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return InventoryProductSummary(
      id: id,
      sku: json['sku'] as String?,
      name: json['name'] as String?,
      barcode: json['barcode'] as String?,
    );
  }
}

/// Una fila de `GET /api/v1/inventory` (ver §13.8 contexto front).
class InventoryLine {
  const InventoryLine({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.reserved,
    this.minStock,
    this.averageUnitCostFunctional,
    this.totalCostFunctional,
    this.product,
  });

  /// Producto activo en catálogo sin fila en `GET /inventory` (aún sin movimientos).
  /// `id` vacío distingue de líneas servidor; el detalle B2 resuelve por `productId`.
  factory InventoryLine.syntheticZeroStock({
    required String productId,
    required String sku,
    required String name,
    String? barcode,
    String? minStock,
  }) {
    return InventoryLine(
      id: '',
      productId: productId,
      quantity: '0',
      reserved: '0',
      minStock: minStock,
      product: InventoryProductSummary(
        id: productId,
        sku: sku,
        name: name,
        barcode: barcode,
      ),
    );
  }

  bool get isSyntheticInventoryRow => id.isEmpty;

  final String id;
  final String productId;
  final String quantity;
  final String reserved;

  /// Umbral para alertas “bajo mínimo” (`GET /inventory`); opcional.
  final String? minStock;
  final String? averageUnitCostFunctional;
  final String? totalCostFunctional;
  final InventoryProductSummary? product;

  String get displayName => product?.name?.trim().isNotEmpty == true
      ? product!.name!.trim()
      : 'Producto $productId';

  String get displaySku =>
      product?.sku?.trim().isNotEmpty == true ? product!.sku!.trim() : '—';

  double? get quantityAsDouble => double.tryParse(quantity.trim());

  double? get minStockAsDouble {
    final m = minStock?.trim();
    if (m == null || m.isEmpty) return null;
    return double.tryParse(m);
  }

  /// `quantity <= 0` (incl. sintéticos sin movimientos).
  bool get isOutOfStock {
    final q = quantityAsDouble ?? 0;
    return q <= 0;
  }

  /// `quantity > 0` y `quantity <= minStock` con `minStock` > 0 definido.
  bool get isBelowMinimumStock {
    final q = quantityAsDouble ?? 0;
    if (q <= 0) return false;
    final min = minStockAsDouble;
    if (min == null || min <= 0) return false;
    return q <= min;
  }

  static InventoryLine fromJson(Map<String, dynamic> json) {
    final productRaw = json['product'];
    Map<String, dynamic>? productMap;
    if (productRaw is Map) {
      productMap = Map<String, dynamic>.from(productRaw);
    }
    final minStr = json['minStock']?.toString().trim();
    return InventoryLine(
      id: json['id']?.toString() ?? '',
      productId: json['productId']?.toString() ?? '',
      quantity: json['quantity']?.toString() ?? '0',
      reserved: json['reserved']?.toString() ?? '0',
      minStock: (minStr == null || minStr.isEmpty) ? null : minStr,
      averageUnitCostFunctional: json['averageUnitCostFunctional']?.toString(),
      totalCostFunctional: json['totalCostFunctional']?.toString(),
      product: InventoryProductSummary.fromJson(productMap),
    );
  }
}
