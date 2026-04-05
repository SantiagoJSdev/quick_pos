import 'api_client.dart';

class PurchasesApi {
  PurchasesApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/purchases` — `FRONTEND_INTEGRATION_CONTEXT.md` §13.10.
  Future<Map<String, dynamic>> createPurchase(
    String storeId,
    Map<String, dynamic> body,
  ) {
    return _client.postJson('/purchases', storeId, body);
  }
}
