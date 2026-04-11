import '../idempotency/client_mutation_id.dart';
import '../storage/local_prefs.dart';
import '../api/sync_api.dart';

/// `opType: NOOP` — conectividad / idempotencia (`SYNC_CONTRACTS.md`). No cola local.
Future<Map<String, dynamic>> submitSyncNoop({
  required SyncApi syncApi,
  required String storeId,
  required LocalPrefs prefs,
  required String deviceId,
  required String appVersion,
}) async {
  final since = await prefs.getSyncPullLastVersion();
  final now = DateTime.now().toUtc().toIso8601String();
  return syncApi.push(storeId, {
    'deviceId': deviceId,
    'appVersion': appVersion,
    'clientTime': now,
    'lastServerVersion': since,
    'ops': [
      {
        'opId': ClientMutationId.newId(),
        'opType': 'NOOP',
        'timestamp': now,
        'payload': <String, dynamic>{},
      },
    ],
  });
}
