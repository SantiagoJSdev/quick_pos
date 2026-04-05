import '../api/api_error.dart';
import '../api/sync_api.dart';
import '../storage/local_prefs.dart';

/// Resultado de `GET /sync/pull` (avance de watermark; ops sin aplicar en catálogo local aún).
class PullSyncResult {
  const PullSyncResult({
    required this.ok,
    this.opsReceived = 0,
    this.watermark,
    this.errorMessage,
  });

  final bool ok;
  final int opsReceived;
  final int? watermark;
  final String? errorMessage;
}

/// Páginas `sync/pull` hasta `hasMore == false` y persiste `toVersion` como watermark.
Future<PullSyncResult> pullSyncAdvanceWatermark({
  required String storeId,
  required LocalPrefs prefs,
  required SyncApi syncApi,
  int limit = 500,
}) async {
  try {
    var since = await prefs.getSyncPullLastVersion();
    var totalOps = 0;
    while (true) {
      final res = await syncApi.pull(storeId, since: since, limit: limit);
      final rawOps = res['ops'];
      if (rawOps is List) {
        totalOps += rawOps.length;
      }
      final toVersion = (res['toVersion'] as num?)?.toInt();
      if (toVersion != null) {
        await prefs.setSyncPullLastVersion(toVersion);
        since = toVersion;
      }
      final hasMore = res['hasMore'] == true;
      if (!hasMore) break;
      if (toVersion == null) break;
    }
    return PullSyncResult(
      ok: true,
      opsReceived: totalOps,
      watermark: since,
    );
  } on ApiError catch (e) {
    return PullSyncResult(
      ok: false,
      errorMessage: e.userMessage,
    );
  } catch (e) {
    return PullSyncResult(
      ok: false,
      errorMessage: e.toString(),
    );
  }
}
