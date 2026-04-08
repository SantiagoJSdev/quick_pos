import '../api/products_api.dart';
import '../storage/local_prefs.dart';
import 'catalog_invalidation_bus.dart';
import 'pending_catalog_mutation_entry.dart';

Future<void> flushPendingCatalogMutations({
  required String storeId,
  required LocalPrefs prefs,
  required ProductsApi productsApi,
  CatalogInvalidationBus? catalogInvalidation,
}) async {
  final all = await prefs.loadPendingCatalogMutations();
  if (all.isEmpty) return;
  final mine = all.where((e) => e.storeId == storeId).toList()
    ..sort((a, b) => a.createdAtIso.compareTo(b.createdAtIso));
  if (mine.isEmpty) return;

  var pending = List<PendingCatalogMutationEntry>.from(all);
  var cache = await prefs.loadCatalogProductsCache();

  for (final e in mine) {
    try {
      if (e.type == PendingCatalogMutationEntry.typeCreate) {
        final body = e.body;
        if (body == null) continue;
        final created = await productsApi.createProduct(storeId, body);
        if (e.localTempId != null && e.localTempId!.isNotEmpty) {
          final i = cache.indexWhere((p) => p.id == e.localTempId);
          if (i >= 0) {
            cache[i] = created;
          } else {
            cache.add(created);
          }
        } else {
          cache.removeWhere((p) => p.id == created.id);
          cache.add(created);
        }
        catalogInvalidation?.invalidateFromLocalMutation(productIds: {created.id});
      } else if (e.type == PendingCatalogMutationEntry.typeCreateWithStock) {
        final body = e.body;
        final key = e.idempotencyKey?.trim() ?? '';
        if (body == null || key.isEmpty) continue;
        final created = await productsApi.createProductWithStock(
          storeId,
          body,
          idempotencyKey: key,
        );
        if (e.localTempId != null && e.localTempId!.isNotEmpty) {
          final i = cache.indexWhere((p) => p.id == e.localTempId);
          if (i >= 0) {
            cache[i] = created.product;
          } else {
            cache.add(created.product);
          }
        } else {
          cache.removeWhere((p) => p.id == created.product.id);
          cache.add(created.product);
        }
        catalogInvalidation
            ?.invalidateFromLocalMutation(productIds: {created.product.id});
      } else if (e.type == PendingCatalogMutationEntry.typeUpdate) {
        final pid = e.productId?.trim() ?? '';
        final body = e.body;
        if (pid.isEmpty || body == null) continue;
        final updated = await productsApi.updateProduct(storeId, pid, body);
        final i = cache.indexWhere((p) => p.id == updated.id);
        if (i >= 0) cache[i] = updated;
        catalogInvalidation?.invalidateFromLocalMutation(productIds: {updated.id});
      } else if (e.type == PendingCatalogMutationEntry.typeDeactivate) {
        final pid = e.productId?.trim() ?? '';
        if (pid.isEmpty) continue;
        await productsApi.deactivateProduct(storeId, pid);
        cache.removeWhere((p) => p.id == pid);
        catalogInvalidation?.invalidateFromLocalMutation(productIds: {pid});
      }
      pending.removeWhere((x) => x.opId == e.opId);
    } catch (_) {
      break;
    }
  }

  await prefs.saveCatalogProductsCache(cache);
  await prefs.savePendingCatalogMutations(pending);
}
