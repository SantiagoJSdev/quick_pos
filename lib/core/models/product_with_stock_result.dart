import 'catalog_product.dart';

/// Respuesta de `POST /api/v1/products-with-stock` (M7).
class ProductWithStockResult {
  const ProductWithStockResult({required this.product, this.inventory});

  final CatalogProduct product;
  final Map<String, dynamic>? inventory;

  static ProductWithStockResult fromJson(Map<String, dynamic> json) {
    // Formas aceptadas:
    // 1) { "product": {...}, "inventory": {...} }
    // 2) producto en la raíz (+ inventory opcional)
    final rawP = json['product'];
    final Map<String, dynamic> productMap;
    if (rawP is Map) {
      productMap = Map<String, dynamic>.from(rawP);
    } else if (json['id'] != null && json['name'] != null) {
      productMap = Map<String, dynamic>.from(json)
        ..remove('inventory')
        ..remove('initialStock')
        ..remove('movement');
    } else {
      throw const FormatException(
        'products-with-stock: falta objeto product (ni anidado ni en raíz)',
      );
    }

    final invRaw = json['inventory'];
    Map<String, dynamic>? inv;
    if (invRaw is Map) {
      inv = Map<String, dynamic>.from(invRaw);
    }

    return ProductWithStockResult(
      product: CatalogProduct.fromJson(productMap),
      inventory: inv,
    );
  }
}
