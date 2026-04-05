import '../storage/local_prefs.dart';
import '../api/sync_api.dart';
import 'pending_sales_flush.dart';
import 'sync_pull.dart';

/// Un ciclo: pull (watermark) + vaciado de cola `sync/push`.
class SyncCycleResult {
  const SyncCycleResult({
    this.pullError,
    this.pullOpsReceived = 0,
    required this.flush,
  });

  final String? pullError;
  final int pullOpsReceived;
  final SyncFlushResult flush;
}

Future<SyncCycleResult> runSyncCycle({
  required String storeId,
  required LocalPrefs prefs,
  required SyncApi syncApi,
  required String deviceId,
  required String appVersion,
  bool doPull = true,
  bool doFlush = true,
}) async {
  String? pullErr;
  var pullOps = 0;
  if (doPull) {
    final pr = await pullSyncAdvanceWatermark(
      storeId: storeId,
      prefs: prefs,
      syncApi: syncApi,
    );
    if (!pr.ok) {
      pullErr = pr.errorMessage;
    } else {
      pullOps = pr.opsReceived;
    }
  }

  final flush = doFlush
      ? await flushPendingSyncOpsForStore(
          storeId: storeId,
          prefs: prefs,
          syncApi: syncApi,
          deviceId: deviceId,
          appVersion: appVersion,
        )
      : const SyncFlushResult(sentCount: 0, removedOpIds: []);

  return SyncCycleResult(
    pullError: pullErr,
    pullOpsReceived: pullOps,
    flush: flush,
  );
}
