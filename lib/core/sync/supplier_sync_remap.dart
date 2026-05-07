import 'pending_purchase_receive_entry.dart';
import 'pending_supplier_mutation_entry.dart';

/// `acked[].supplier` en `SUPPLIER_CREATE`: `clientSupplierId` + `supplierId` servidor.
Map<String, String> supplierAckClientToServerIds(List<dynamic> ackList) {
  final map = <String, String>{};
  for (final item in ackList) {
    if (item is! Map) continue;
    final sup = item['supplier'];
    if (sup is! Map) continue;
    final clientId = sup['clientSupplierId']?.toString();
    final serverId = sup['supplierId']?.toString();
    if (clientId != null &&
        clientId.isNotEmpty &&
        serverId != null &&
        serverId.isNotEmpty) {
      map[clientId] = serverId;
    }
  }
  return map;
}

void remapSupplierIdInPendingPurchases(
  Iterable<PendingPurchaseReceiveEntry> list,
  Map<String, String> clientToServer,
) {
  if (clientToServer.isEmpty) return;
  for (final e in list) {
    final sid = e.purchase['supplierId']?.toString();
    if (sid == null || sid.isEmpty) continue;
    final to = clientToServer[sid];
    if (to != null) e.purchase['supplierId'] = to;
  }
}

void remapSupplierIdInPendingSupplierMutations(
  Iterable<PendingSupplierMutationEntry> list,
  Map<String, String> clientToServer,
) {
  if (clientToServer.isEmpty) return;
  for (final e in list) {
    if (e.opType == 'SUPPLIER_CREATE') continue;
    final sid = e.supplier['supplierId']?.toString();
    if (sid == null || sid.isEmpty) continue;
    final to = clientToServer[sid];
    if (to != null) e.supplier['supplierId'] = to;
  }
}
