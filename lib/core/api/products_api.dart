import '../models/catalog_product.dart';
import 'api_client.dart';

class ProductsApi {
  ProductsApi(this._client);

  final ApiClient _client;

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
