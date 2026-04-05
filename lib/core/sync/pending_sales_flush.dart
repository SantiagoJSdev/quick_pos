import '../api/api_error.dart';
import '../api/sync_api.dart';
import '../storage/local_prefs.dart';

/// Resultado de intentar vaciar la cola hacia el servidor.
class PendingSalesFlushResult {
  const PendingSalesFlushResult({
    required this.sentCount,
    required this.removedOpIds,
    this.hadTransportFailure = false,
    this.apiMessage,
  });

  final int sentCount;
  final List<String> removedOpIds;
  final bool hadTransportFailure;
  final String? apiMessage;

  int get removedCount => removedOpIds.length;
}

/// Envía hasta 200 ops `SALE` pendientes vía `sync/push`; quita de cola las `acked` y `skipped`.
Future<PendingSalesFlushResult> flushPendingSalesForStore({
  required String storeId,
  required LocalPrefs prefs,
  required SyncApi syncApi,
  required String deviceId,
  required String appVersion,
}) async {
  final all = await prefs.loadPendingSales();
  final pending = all.where((e) => e.storeId == storeId).toList();
  if (pending.isEmpty) {
    return const PendingSalesFlushResult(sentCount: 0, removedOpIds: []);
  }

  final batch = pending.take(200).toList();
  final lastPull = await prefs.getSyncPullLastVersion();

  final ops = <Map<String, dynamic>>[];
  for (final e in batch) {
    ops.add({
      'opId': e.opId,
      'opType': 'SALE',
      'timestamp': e.opTimestampIso,
      'payload': <String, dynamic>{'sale': e.sale},
    });
  }

  final body = <String, dynamic>{
    'deviceId': deviceId,
    'appVersion': appVersion,
    'clientTime': DateTime.now().toUtc().toIso8601String(),
    'lastServerVersion': lastPull,
    'ops': ops,
  };

  try {
    final res = await syncApi.push(storeId, body);
    final remove = <String>{};
    void collectOpIds(String key) {
      final list = res[key];
      if (list is! List) return;
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['opId']?.toString();
        if (id != null && id.isNotEmpty) remove.add(id);
      }
    }

    collectOpIds('acked');
    collectOpIds('skipped');

    final remaining =
        all.where((e) => !remove.contains(e.opId)).toList(growable: false);
    await prefs.savePendingSales(remaining);

    return PendingSalesFlushResult(
      sentCount: batch.length,
      removedOpIds: remove.toList(),
    );
  } on ApiError catch (e) {
    return PendingSalesFlushResult(
      sentCount: batch.length,
      removedOpIds: const [],
      apiMessage: e.userMessage,
    );
  } catch (e) {
    return PendingSalesFlushResult(
      sentCount: batch.length,
      removedOpIds: const [],
      hadTransportFailure: true,
      apiMessage: e.toString(),
    );
  }
}
