/// Analiza ops de `GET /sync/pull` y detecta mutaciones de catálogo (`PRODUCT_*`).
///
/// Puro (sin I/O): testeable y reutilizable desde [pullSyncAdvanceWatermark].
class PullCatalogMutationSummary {
  const PullCatalogMutationSummary({
    required this.hadMutation,
    this.affectedProductIds = const {},
  });

  final bool hadMutation;
  final Set<String> affectedProductIds;
}

PullCatalogMutationSummary summarizePullOpsProductChanges(List<dynamic> ops) {
  final ids = <String>{};
  var any = false;
  for (final raw in ops) {
    if (raw is! Map) continue;
    final m = raw.map((k, v) => MapEntry(k.toString(), v));
    final t = m['opType']?.toString();
    if (t != 'PRODUCT_CREATED' &&
        t != 'PRODUCT_UPDATED' &&
        t != 'PRODUCT_DEACTIVATED') {
      continue;
    }
    any = true;
    final p = m['payload'];
    if (p is Map) {
      final id = p['productId']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
    }
  }
  return PullCatalogMutationSummary(hadMutation: any, affectedProductIds: ids);
}
