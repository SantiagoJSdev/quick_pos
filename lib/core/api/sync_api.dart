import 'api_client.dart';

class SyncApi {
  SyncApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/sync/push` — `SYNC_CONTRACTS.md`.
  Future<Map<String, dynamic>> push(
    String storeId,
    Map<String, dynamic> body,
  ) {
    return _client.postJson('/sync/push', storeId, body);
  }
}
