import '../models/sales_list_page.dart';
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

  /// `GET /api/v1/sales` — historial paginado (`format=object` default). Ver `docs/BACKEND_SALES_HISTORY_API.md`.
  /// No mezclar `cursor` con `format=array`.
  Future<SalesListPage> listSales(
    String storeId, {
    String? dateFrom,
    String? dateTo,
    String? deviceId,
    int limit = 50,
    String? cursor,
  }) async {
    final q = <String, String>{
      'limit': '${limit.clamp(1, 200)}',
      if (dateFrom != null && dateFrom.isNotEmpty) 'dateFrom': dateFrom,
      if (dateTo != null && dateTo.isNotEmpty) 'dateTo': dateTo,
      if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final raw = await _client.getJson('/sales', storeId, query: q);
    return SalesListPage.fromJson(raw);
  }
}
