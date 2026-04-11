import '../api/api_error.dart';
import '../api/sync_api.dart';
import '../storage/local_prefs.dart';

/// Resultado de `sync/push` sobre la cola local (ventas, ajustes, compras, devoluciones).
class SyncFlushResult {
  const SyncFlushResult({
    required this.sentCount,
    required this.removedOpIds,
    this.hadTransportFailure = false,
    this.hadRetryableFailure = false,
    this.hadManualReviewFailure = false,
    this.apiMessage,
  });

  final int sentCount;
  final List<String> removedOpIds;
  final bool hadTransportFailure;
  final bool hadRetryableFailure;
  final bool hadManualReviewFailure;
  final String? apiMessage;

  int get removedCount => removedOpIds.length;
}

/// Compatibilidad con código que aún nombre el tipo anterior.
typedef PendingSalesFlushResult = SyncFlushResult;

/// Mezcla `SALE`, `INVENTORY_ADJUST`, `PURCHASE_RECEIVE` y `SALE_RETURN` pendientes (orden por `timestamp`), hasta 200 ops.
Future<SyncFlushResult> flushPendingSyncOpsForStore({
  required String storeId,
  required LocalPrefs prefs,
  required SyncApi syncApi,
  required String deviceId,
  required String appVersion,
}) async {
  final allSales = await prefs.loadPendingSales();
  final allAdjusts = await prefs.loadPendingInventoryAdjusts();
  final allPurchases = await prefs.loadPendingPurchaseReceives();
  final allReturns = await prefs.loadPendingSaleReturns();

  final saleQueue = allSales
      .where((e) => e.storeId == storeId)
      .toList(growable: false);
  final adjQueue = allAdjusts
      .where((e) => e.storeId == storeId)
      .toList(growable: false);
  final purchaseQueue = allPurchases
      .where((e) => e.storeId == storeId)
      .toList(growable: false);
  final returnQueue = allReturns
      .where((e) => e.storeId == storeId)
      .toList(growable: false);

  if (saleQueue.isEmpty &&
      adjQueue.isEmpty &&
      purchaseQueue.isEmpty &&
      returnQueue.isEmpty) {
    return const SyncFlushResult(sentCount: 0, removedOpIds: []);
  }

  final merged = <Map<String, Object?>>[];
  for (final e in saleQueue) {
    merged.add({
      'opId': e.opId,
      'opType': 'SALE',
      'timestamp': e.opTimestampIso,
      'payload': <String, dynamic>{'sale': e.sale},
    });
  }
  for (final e in adjQueue) {
    merged.add({
      'opId': e.opId,
      'opType': 'INVENTORY_ADJUST',
      'timestamp': e.opTimestampIso,
      'payload': e.payload,
    });
  }
  for (final e in purchaseQueue) {
    merged.add({
      'opId': e.opId,
      'opType': 'PURCHASE_RECEIVE',
      'timestamp': e.opTimestampIso,
      'payload': <String, dynamic>{'purchase': e.purchase},
    });
  }
  for (final e in returnQueue) {
    merged.add({
      'opId': e.opId,
      'opType': 'SALE_RETURN',
      'timestamp': e.opTimestampIso,
      'payload': <String, dynamic>{'saleReturn': e.saleReturn},
    });
  }
  merged.sort(
    (a, b) => (a['timestamp']! as String).compareTo(b['timestamp']! as String),
  );

  final batch = merged.take(200).toList();
  final lastPull = await prefs.getSyncPullLastVersion();

  final ops = <Map<String, dynamic>>[];
  for (final m in batch) {
    ops.add({
      'opId': m['opId'],
      'opType': m['opType'],
      'timestamp': m['timestamp'],
      'payload': m['payload'],
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

    final remainingSales = allSales
        .where((e) => !remove.contains(e.opId))
        .toList(growable: false);
    final remainingAdj = allAdjusts
        .where((e) => !remove.contains(e.opId))
        .toList(growable: false);
    final remainingPurchases = allPurchases
        .where((e) => !remove.contains(e.opId))
        .toList(growable: false);
    final remainingReturns = allReturns
        .where((e) => !remove.contains(e.opId))
        .toList(growable: false);
    await prefs.savePendingSales(remainingSales);
    await prefs.savePendingInventoryAdjusts(remainingAdj);
    await prefs.savePendingPurchaseReceives(remainingPurchases);
    await prefs.savePendingSaleReturns(remainingReturns);

    for (final e in saleQueue) {
      if (!remove.contains(e.opId)) continue;
      final cid = e.sale['id']?.toString();
      if (cid != null && cid.isNotEmpty) {
        await prefs.markRecentSaleTicketSyncedByClientId(cid);
      }
    }

    return SyncFlushResult(
      sentCount: batch.length,
      removedOpIds: remove.toList(),
    );
  } on ApiError catch (e) {
    return SyncFlushResult(
      sentCount: batch.length,
      removedOpIds: const [],
      hadRetryableFailure: e.isRetryableSyncFailure,
      hadManualReviewFailure: e.isManualReviewSyncFailure,
      apiMessage: e.userMessageForSupport,
    );
  } catch (e) {
    return SyncFlushResult(
      sentCount: batch.length,
      removedOpIds: const [],
      hadTransportFailure: true,
      apiMessage: e.toString(),
    );
  }
}

@Deprecated('Use flushPendingSyncOpsForStore')
Future<SyncFlushResult> flushPendingSalesForStore({
  required String storeId,
  required LocalPrefs prefs,
  required SyncApi syncApi,
  required String deviceId,
  required String appVersion,
}) {
  return flushPendingSyncOpsForStore(
    storeId: storeId,
    prefs: prefs,
    syncApi: syncApi,
    deviceId: deviceId,
    appVersion: appVersion,
  );
}
