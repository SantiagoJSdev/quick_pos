import '../models/supplier.dart';
import 'api_client.dart';

class SuppliersApi {
  SuppliersApi(this._client);

  final ApiClient _client;

  /// `GET /api/v1/suppliers` — `active`: `true` (default), `false`, `all`.
  Future<SupplierListPage> listSuppliers(
    String storeId, {
    String? q,
    String? cursor,
    int limit = 50,
    String active = 'true',
  }) async {
    final capped = limit.clamp(1, 200);
    final query = <String, String>{'limit': '$capped', 'active': active};
    final trimmedQ = q?.trim();
    if (trimmedQ != null && trimmedQ.isNotEmpty) {
      query['q'] = trimmedQ;
    }
    final trimmedCursor = cursor?.trim();
    if (trimmedCursor != null && trimmedCursor.isNotEmpty) {
      query['cursor'] = trimmedCursor;
    }
    final map = await _client.getJson('/suppliers', storeId, query: query);
    final rawItems = map['items'];
    final items = <Supplier>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(Supplier.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    final next = map['nextCursor']?.toString().trim();
    return SupplierListPage(
      items: items,
      nextCursor: (next == null || next.isEmpty) ? null : next,
    );
  }

  /// `GET /api/v1/suppliers/:id`
  Future<Supplier> getSupplier(String storeId, String id) async {
    final map = await _client.getJson('/suppliers/$id', storeId);
    return Supplier.fromJson(map);
  }

  /// `POST /api/v1/suppliers` — **201** + cuerpo.
  Future<Supplier> createSupplier(
    String storeId,
    Map<String, dynamic> body,
  ) async {
    final map = await _client.postJson('/suppliers', storeId, body);
    return Supplier.fromJson(map);
  }

  /// `PATCH /api/v1/suppliers/:id`
  Future<Supplier> patchSupplier(
    String storeId,
    String id,
    Map<String, dynamic> body,
  ) async {
    final map = await _client.patchJson('/suppliers/$id', storeId, body);
    return Supplier.fromJson(map);
  }

  /// `DELETE /api/v1/suppliers/:id` — soft delete; **200** + objeto.
  Future<Supplier> deactivateSupplier(String storeId, String id) async {
    final map = await _client.deleteJson('/suppliers/$id', storeId);
    return Supplier.fromJson(map);
  }
}
