import '../api/api_error.dart';
import '../api/sync_api.dart';
import '../catalog/catalog_invalidation_bus.dart';
import '../storage/local_prefs.dart';
import 'pull_catalog_ops.dart';

/// Resultado de `GET /sync/pull` (watermark + señal de catálogo).
class PullSyncResult {
  const PullSyncResult({
    required this.ok,
    this.opsReceived = 0,
    this.watermark,
    this.errorMessage,
    this.catalogInvalidated = false,
  });

  final bool ok;
  final int opsReceived;
  final int? watermark;
  final String? errorMessage;

  /// Hubo al menos un `PRODUCT_*` en alguna página (se notificó al [CatalogInvalidationBus]).
  final bool catalogInvalidated;
}

/// Páginas `sync/pull` hasta `hasMore == false`, persiste `toVersion` y materializa
/// catálogo vía invalidación (refetch REST en pantallas).
Future<PullSyncResult> pullSyncAdvanceWatermark({
  required String storeId,
  required LocalPrefs prefs,
  required SyncApi syncApi,
  CatalogInvalidationBus? catalogInvalidation,
  int limit = 500,
}) async {
  try {
    var since = await prefs.getSyncPullLastVersion();
    var totalOps = 0;
    final accumulatedProductIds = <String>{};
    var hadProductPullMutation = false;
    while (true) {
      final res = await syncApi.pull(storeId, since: since, limit: limit);
      final rawOps = res['ops'];
      if (rawOps is List) {
        totalOps += rawOps.length;
        final summary = summarizePullOpsProductChanges(rawOps);
        if (summary.hadMutation) {
          hadProductPullMutation = true;
          accumulatedProductIds.addAll(summary.affectedProductIds);
        }
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

    if (hadProductPullMutation && catalogInvalidation != null) {
      catalogInvalidation.invalidateFromPull(
        productIds: accumulatedProductIds.isEmpty
            ? null
            : accumulatedProductIds,
      );
    }

    return PullSyncResult(
      ok: true,
      opsReceived: totalOps,
      watermark: since,
      catalogInvalidated: hadProductPullMutation,
    );
  } on ApiError catch (e) {
    return PullSyncResult(ok: false, errorMessage: e.userMessageForSupport);
  } catch (e) {
    return PullSyncResult(ok: false, errorMessage: e.toString());
  }
}
