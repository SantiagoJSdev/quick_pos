import 'api_client.dart';

class SaleReturnsApi {
  SaleReturnsApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/sale-returns` — `FRONTEND_INTEGRATION_CONTEXT.md` §13.11.
  Future<Map<String, dynamic>> createSaleReturn(
    String storeId,
    Map<String, dynamic> body,
  ) {
    return _client.postJson('/sale-returns', storeId, body);
  }

  /// `GET /api/v1/sale-returns/:id`
  Future<Map<String, dynamic>> getSaleReturn(String storeId, String id) {
    return _client.getJson('/sale-returns/$id', storeId);
  }
}
