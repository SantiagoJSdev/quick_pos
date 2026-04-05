import 'api_client.dart';

class SalesApi {
  SalesApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/sales` — `FRONTEND_INTEGRATION_CONTEXT.md` §13.9.
  Future<Map<String, dynamic>> createSale(
    String storeId,
    Map<String, dynamic> body,
  ) {
    return _client.postJson('/sales', storeId, body);
  }

  /// `GET /api/v1/sales/:id` — detalle con líneas (misma tienda).
  Future<Map<String, dynamic>> getSale(String storeId, String saleId) {
    return _client.getJson('/sales/$saleId', storeId);
  }
}
