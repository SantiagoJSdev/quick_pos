import 'catalog_product.dart';

/// Respuesta de `POST /api/v1/products-with-stock` (M7).
class ProductWithStockResult {
  const ProductWithStockResult({
    required this.product,
    this.inventory,
  });

  final CatalogProduct product;
  final Map<String, dynamic>? inventory;

  static ProductWithStockResult fromJson(Map<String, dynamic> json) {
    final rawP = json['product'];
    if (rawP is! Map) {
      throw FormatException('products-with-stock: falta objeto product');
    }
    final invRaw = json['inventory'];
    Map<String, dynamic>? inv;
    if (invRaw is Map) {
      inv = Map<String, dynamic>.from(invRaw);
    }
    return ProductWithStockResult(
      product: CatalogProduct.fromJson(Map<String, dynamic>.from(rawP)),
      inventory: inv,
    );
  }
}
