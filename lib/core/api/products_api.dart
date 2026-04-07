import '../models/catalog_product.dart';
import '../models/product_with_stock_result.dart';
import '../pos/product_with_stock_payload.dart';
import 'api_client.dart';

class ProductsApi {
  ProductsApi(this._client);

  final ApiClient _client;

  /// `GET /api/v1/products/:id` — `null` si no existe o error de red/API.
  Future<CatalogProduct?> getProduct(
    String storeId,
    String productId,
  ) async {
    try {
      final json = await _client.getJson(
        '/products/$productId',
        storeId,
      );
      return CatalogProduct.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<List<CatalogProduct>> listProducts(
    String storeId, {
    bool includeInactive = false,
    String source = 'auto',
  }) async {
    final raw = await _client.getJsonList(
      '/products',
      storeId,
      query: {
        'includeInactive': includeInactive.toString(),
        'source': source,
      },
    );
    return raw.map(CatalogProduct.fromJson).toList();
  }

  Future<CatalogProduct> createProduct(
    String storeId,
    Map<String, dynamic> body,
  ) async {
    final json = await _client.postJson('/products', storeId, body);
    return CatalogProduct.fromJson(json);
  }

  /// `POST /api/v1/products-with-stock` — cabecera **`Idempotency-Key`** obligatoria (UUID).
  Future<ProductWithStockResult> createProductWithStock(
    String storeId,
    Map<String, dynamic> body, {
    required String idempotencyKey,
  }) async {
    final json = await _client.postJson(
      '/products-with-stock',
      storeId,
      body,
      idempotencyKey: idempotencyKey,
    );
    return ProductWithStockResult.fromJson(json);
  }

  /// Expuesto para el sheet (misma forma que [createProductWithStock]).
  static Map<String, dynamic> buildWithStockBody({
    required CatalogProduct product,
    required String quantity,
    required String reason,
    required String initialStockOpId,
    String? unitCostFunctional,
  }) {
    return ProductWithStockPayload.build(
      product: product,
      quantity: quantity,
      reason: reason,
      initialStockOpId: initialStockOpId,
      unitCostFunctional: unitCostFunctional,
    );
  }

  static String canonicalBodyJson(Map<String, dynamic> body) =>
      ProductWithStockPayload.canonicalJson(body);

  Future<CatalogProduct> updateProduct(
    String storeId,
    String productId,
    Map<String, dynamic> body,
  ) async {
    final json = await _client.patchJson('/products/$productId', storeId, body);
    return CatalogProduct.fromJson(json);
  }

  Future<void> deactivateProduct(String storeId, String productId) {
    return _client.deleteNoContent('/products/$productId', storeId);
  }
}
