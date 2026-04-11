import 'api_client.dart';

class SyncApi {
  SyncApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/sync/push` — `SYNC_CONTRACTS.md`.
  Future<Map<String, dynamic>> push(String storeId, Map<String, dynamic> body) {
    return _client.postJson('/sync/push', storeId, body);
  }

  /// `GET /api/v1/sync/pull?since=&limit=` — watermark global (`SYNC_CONTRACTS.md`).
  Future<Map<String, dynamic>> pull(
    String storeId, {
    required int since,
    int limit = 500,
  }) {
    return _client.getJson(
      '/sync/pull',
      storeId,
      query: {'since': '$since', 'limit': '$limit'},
    );
  }
}
