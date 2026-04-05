import '../models/inventory_adjustment_result.dart';
import '../models/inventory_line.dart';
import '../models/stock_movement.dart';
import 'api_client.dart';
import 'api_error.dart';

class InventoryApi {
  InventoryApi(this._client);

  final ApiClient _client;

  /// `GET /api/v1/inventory` — array de líneas por tienda.
  Future<List<InventoryLine>> listInventory(String storeId) async {
    final raw = await _client.getJsonList('/inventory', storeId);
    return raw.map(InventoryLine.fromJson).toList();
  }

  /// `GET /api/v1/inventory/:productId` — una línea; `null` si **404** (aún no hay ítem).
  Future<InventoryLine?> getInventoryLine(
    String storeId,
    String productId,
  ) async {
    try {
      final json = await _client.getJson('/inventory/$productId', storeId);
      return InventoryLine.fromJson(json);
    } on ApiError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// `GET /api/v1/inventory/movements?productId=<opcional>&limit=<1-500>` — cuerpo = array en raíz.
  Future<List<StockMovement>> listMovements(
    String storeId, {
    String? productId,
    int limit = 100,
  }) async {
    final capped = limit.clamp(1, 500);
    final query = <String, String>{'limit': capped.toString()};
    final pid = productId?.trim();
    if (pid != null && pid.isNotEmpty) {
      query['productId'] = pid;
    }
    final raw = await _client.getJsonList(
      '/inventory/movements',
      storeId,
      query: query,
    );
    return raw.map(StockMovement.fromJson).toList();
  }

  /// `POST /api/v1/inventory/adjustments` — `IN_ADJUST` / `OUT_ADJUST`, etc.
  Future<InventoryAdjustmentResult> postAdjustment(
    String storeId,
    Map<String, dynamic> body,
  ) async {
    final json = await _client.postJson('/inventory/adjustments', storeId, body);
    return InventoryAdjustmentResult.fromJson(json);
  }
}
