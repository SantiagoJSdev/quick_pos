import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/active_pos_cart_draft.dart';
import '../models/cash_session.dart';
import '../models/held_ticket.dart';
import '../models/local_supplier.dart';
import '../models/recent_sale_ticket.dart';
import '../models/catalog_product.dart';
import '../models/business_settings.dart';
import '../models/inventory_line.dart';
import '../models/latest_exchange_rate.dart';
import '../models/sales_list_page.dart';
import '../photos/pending_product_photo_upload_entry.dart';
import '../pos/sale_checkout_payload.dart';
import '../catalog/pending_catalog_mutation_entry.dart';
import '../sync/pending_inventory_adjust_entry.dart';
import '../sync/pending_purchase_receive_entry.dart';
import '../sync/pending_sale_entry.dart';
import '../sync/pending_sale_return_entry.dart';
import '../sync/pending_supplier_mutation_entry.dart';

const _kStoreId = 'store_id';
const _kManualForceOfflineV1 = 'manual_force_offline_v1';
const _kDeviceId = 'device_id';
const _kLocalSuppliers = 'local_suppliers_v1';
const _kPendingSalesV1 = 'pending_sales_v1';
const _kPendingInvAdjustV1 = 'pending_inventory_adjusts_v1';
const _kPendingPurchaseReceiveV1 = 'pending_purchase_receive_v1';
const _kPendingSaleReturnV1 = 'pending_sale_return_v1';
const _kPendingSupplierMutationsV1 = 'pending_supplier_mutations_v1';
const _kSyncPullSinceV1 = 'sync_pull_since_v1';
const _kRecentSalesV1 = 'recent_sales_v1';
const _kTicketDisplaySeqStateV1 = 'ticket_display_seq_state_v1';
const _kHeldTicketsV1 = 'held_tickets_v1';
const _kActivePosCartPrefix = 'active_pos_cart_v1_';
const _kLocalCashSessionPrefix = 'local_cash_session_v1_';
const _kCatalogProductsCacheV1 = 'catalog_products_cache_v1';
const _kPendingCatalogMutationsV1 = 'pending_catalog_mutations_v1';
const _kBusinessSettingsCachePrefix = 'business_settings_cache_v1_';
const _kPosFxPairCachePrefix = 'pos_fx_pair_cache_v1_';
const _kInventoryCachePrefix = 'inventory_cache_v1_';
const _kSalesGeneralCachePrefix = 'sales_general_cache_v1_';
const _kLatestRateCachePrefix = 'latest_rate_cache_v1_';
const _kApiBaseUrlOverrideV1 = 'api_base_url_override_v1';
const _kLastSuccessfulSyncAtV1 = 'last_successful_sync_at_v1';
const _kPendingProductPhotoUploadsV1 = 'pending_product_photo_uploads_v1';
const _kDashboardAccessTokenPrefix = 'dashboard_access_token_v1_';
const _kDashboardKioskCachePrefix = 'dashboard_kiosk_cache_v1_';
const _kCachedDeviceModeV1 = 'cached_device_mode_v1';
const _kCachedDashboardEnabledPrefix = 'cached_dashboard_enabled_v1_';
/// Inventario / Proveedores habilitados en este dispositivo (por tienda + deviceId).
const _kDeviceModuleInventoryPrefix = 'device_module_inventory_v1_';
const _kDeviceModuleSuppliersPrefix = 'device_module_suppliers_v1_';

class LocalPrefs {
  LocalPrefs(this._prefs);

  final SharedPreferences _prefs;
  static const _uuid = Uuid();

  Future<String?> getStoreId() async => _prefs.getString(_kStoreId);

  Future<void> setStoreId(String storeId) =>
      _prefs.setString(_kStoreId, storeId.trim());

  Future<void> clearStoreId() => _prefs.remove(_kStoreId);

  /// Borra **toda** la persistencia local de Quick POS al desvincular el dispositivo.
  ///
  /// Conserva solo [getOrCreateDeviceId] (`deviceId`). La URL del API guardada
  /// en Configuración se borra para que vuelva a aplicar `--dart-define` / default.
  Future<void> clearAllLocalQuickPosDataPreservingDeviceId() async {
    // Sincroniza con disco (Android puede cachear lecturas hasta reload).
    try {
      await _prefs.reload();
    } catch (_) {}
    const keep = {_kDeviceId};
    for (final k in List<String>.from(_prefs.getKeys())) {
      if (keep.contains(k)) continue;
      await _prefs.remove(k);
    }
    try {
      await _prefs.reload();
    } catch (_) {}
  }

  /// Modo offline forzado desde Inicio: persiste hasta que el usuario vuelva a activar online.
  Future<bool> getManualForceOffline() async =>
      _prefs.getBool(_kManualForceOfflineV1) ?? false;

  Future<void> setManualForceOffline(bool value) async =>
      _prefs.setBool(_kManualForceOfflineV1, value);

  Future<String?> getApiBaseUrlOverride() async {
    final raw = _prefs.getString(_kApiBaseUrlOverrideV1);
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<void> setApiBaseUrlOverride(String url) async {
    await _prefs.setString(_kApiBaseUrlOverrideV1, url.trim());
  }

  Future<void> clearApiBaseUrlOverride() async {
    await _prefs.remove(_kApiBaseUrlOverrideV1);
    // Versiones anteriores (resolver Vercel / ngrok).
    await _prefs.remove('api_follow_cloud_resolver_v1');
    await _prefs.remove('pos_api_origin');
    await _prefs.remove('pos_api_origin_updated_at');
  }

  Future<void> markLastSuccessfulSyncNow() async {
    await _prefs.setString(
      _kLastSuccessfulSyncAtV1,
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<DateTime?> loadLastSuccessfulSyncAt() async {
    final raw = _prefs.getString(_kLastSuccessfulSyncAtV1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// Umbral para UX “puede estar desactualizado” (catálogo / historial).
  static const Duration catalogStaleThreshold = Duration(minutes: 30);

  Future<bool> isCatalogLikelyStale({
    Duration threshold = catalogStaleThreshold,
  }) async {
    final at = await loadLastSuccessfulSyncAt();
    if (at == null) return true;
    return DateTime.now().difference(at) > threshold;
  }

  Future<List<PendingProductPhotoUploadEntry>>
  loadPendingProductPhotoUploads() async {
    final raw = _prefs.getString(_kPendingProductPhotoUploadsV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PendingProductPhotoUploadEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final x = PendingProductPhotoUploadEntry.tryFromJson(
          Map<String, dynamic>.from(e),
        );
        if (x != null) out.add(x);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingProductPhotoUploads(
    List<PendingProductPhotoUploadEntry> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kPendingProductPhotoUploadsV1, encoded);
  }

  Future<void> appendPendingProductPhotoUpload(
    PendingProductPhotoUploadEntry entry,
  ) async {
    final list = await loadPendingProductPhotoUploads();
    list.add(entry);
    await savePendingProductPhotoUploads(list);
  }

  /// Tras crear en servidor un producto que en cola era `local_*`, actualiza fotos pendientes.
  Future<void> remapPendingProductPhotoUploadProductId({
    required String storeId,
    required String fromProductId,
    required String toProductId,
  }) async {
    final from = fromProductId.trim();
    final to = toProductId.trim();
    if (from.isEmpty || to.isEmpty || from == to) return;
    final list = await loadPendingProductPhotoUploads();
    var changed = false;
    final next = <PendingProductPhotoUploadEntry>[];
    for (final e in list) {
      if (e.storeId == storeId && e.productId == from) {
        next.add(
          PendingProductPhotoUploadEntry(
            opId: e.opId,
            storeId: e.storeId,
            productId: to,
            localFilePath: e.localFilePath,
            createdAtIso: e.createdAtIso,
            attemptCount: e.attemptCount,
            lastError: e.lastError,
            manualReview: e.manualReview,
          ),
        );
        changed = true;
      } else {
        next.add(e);
      }
    }
    if (changed) await savePendingProductPhotoUploads(next);
  }

  /// UUID v4 estable por instalación (sync / ventas).
  Future<String> getOrCreateDeviceId() async {
    final existing = _prefs.getString(_kDeviceId);
    if (existing != null && existing.isNotEmpty) return existing;
    final id = _uuid.v4();
    await _prefs.setString(_kDeviceId, id);
    return id;
  }

  /// C1 — lista JSON en preferencias (nombre + UUID proveedor).
  Future<List<LocalSupplier>> getLocalSuppliers() async {
    final raw = _prefs.getString(_kLocalSuppliers);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) {
            if (e is! Map) return null;
            return LocalSupplier.fromJson(Map<String, dynamic>.from(e));
          })
          .whereType<LocalSupplier>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLocalSuppliers(List<LocalSupplier> suppliers) async {
    final encoded = jsonEncode(suppliers.map((e) => e.toJson()).toList());
    await _prefs.setString(_kLocalSuppliers, encoded);
  }

  /// Inserta o reemplaza por [LocalSupplier.id] (p. ej. alta offline).
  Future<void> upsertLocalSupplier(LocalSupplier s) async {
    final list = await getLocalSuppliers();
    final i = list.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      list[i] = s;
    } else {
      list.add(s);
    }
    await saveLocalSuppliers(list);
  }

  /// Quita de la caché local (p. ej. baja offline encolada).
  Future<void> removeLocalSupplierById(String supplierId) async {
    final id = supplierId.trim();
    if (id.isEmpty) return;
    final list =
        (await getLocalSuppliers()).where((e) => e.id != id).toList();
    await saveLocalSuppliers(list);
  }

  /// Tras `SUPPLIER_CREATE` ack en sync/push: `clientSupplierId` → id servidor.
  Future<void> applySupplierProvisionalRemapToLocalCache(
    Map<String, String> clientToServer,
  ) async {
    if (clientToServer.isEmpty) return;
    final list = await getLocalSuppliers();
    var changed = false;
    final out = <LocalSupplier>[];
    for (final e in list) {
      final to = clientToServer[e.id];
      if (to != null && to.isNotEmpty) {
        changed = true;
        out.add(LocalSupplier(id: to, name: e.name));
      } else {
        out.add(e);
      }
    }
    final byId = <String, LocalSupplier>{};
    for (final e in out) {
      byId[e.id] = e;
    }
    final merged = byId.values.toList();
    if (changed || merged.length != list.length) {
      await saveLocalSuppliers(merged);
    }
  }

  /// Watermark para `lastServerVersion` en `sync/push` (pull global — § SYNC_CONTRACTS).
  Future<int> getSyncPullLastVersion() async {
    final s = _prefs.getString(_kSyncPullSinceV1);
    if (s == null || s.isEmpty) return 0;
    return int.tryParse(s) ?? 0;
  }

  Future<void> setSyncPullLastVersion(int v) async {
    await _prefs.setString(_kSyncPullSinceV1, '$v');
  }

  Future<List<PendingSaleEntry>> loadPendingSales() async {
    final raw = _prefs.getString(_kPendingSalesV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PendingSaleEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final entry = PendingSaleEntry.tryFromJson(
          Map<String, dynamic>.from(e),
        );
        if (entry != null) out.add(entry);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingSales(List<PendingSaleEntry> items) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kPendingSalesV1, encoded);
  }

  Future<void> appendPendingSale(PendingSaleEntry entry) async {
    final list = await loadPendingSales();
    final saleId = entry.sale['id']?.toString().trim() ?? '';
    if (saleId.isNotEmpty) {
      final i = list.indexWhere(
        (e) =>
            e.storeId == entry.storeId &&
            (e.sale['id']?.toString().trim() ?? '') == saleId,
      );
      if (i >= 0) {
        // Mismo cobro: conservar opId original (evita doble factura al reintentar).
        list[i] = PendingSaleEntry(
          opId: list[i].opId,
          storeId: entry.storeId,
          sale: entry.sale,
          opTimestampIso: list[i].opTimestampIso,
        );
        await savePendingSales(list);
        return;
      }
    }
    list.add(entry);
    await savePendingSales(list);
  }

  /// `opId` ya en cola para este `sale.id`, o null.
  Future<String?> findPendingSaleOpId({
    required String storeId,
    required String saleId,
  }) async {
    final sid = saleId.trim();
    if (sid.isEmpty) return null;
    final list = await loadPendingSales();
    for (final e in list) {
      if (e.storeId != storeId) continue;
      if ((e.sale['id']?.toString().trim() ?? '') == sid) return e.opId;
    }
    return null;
  }

  Future<int> countPendingSalesForStore(String storeId) async {
    final list = await loadPendingSales();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<List<PendingInventoryAdjustEntry>>
  loadPendingInventoryAdjusts() async {
    final raw = _prefs.getString(_kPendingInvAdjustV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PendingInventoryAdjustEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final entry = PendingInventoryAdjustEntry.tryFromJson(
          Map<String, dynamic>.from(e),
        );
        if (entry != null) out.add(entry);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingInventoryAdjusts(
    List<PendingInventoryAdjustEntry> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kPendingInvAdjustV1, encoded);
  }

  Future<void> appendPendingInventoryAdjust(
    PendingInventoryAdjustEntry entry,
  ) async {
    final list = await loadPendingInventoryAdjusts();
    list.add(entry);
    await savePendingInventoryAdjusts(list);
  }

  Future<int> countPendingInventoryAdjustsForStore(String storeId) async {
    final list = await loadPendingInventoryAdjusts();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<List<PendingPurchaseReceiveEntry>>
  loadPendingPurchaseReceives() async {
    final raw = _prefs.getString(_kPendingPurchaseReceiveV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PendingPurchaseReceiveEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final entry = PendingPurchaseReceiveEntry.tryFromJson(
          Map<String, dynamic>.from(e),
        );
        if (entry != null) out.add(entry);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingPurchaseReceives(
    List<PendingPurchaseReceiveEntry> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kPendingPurchaseReceiveV1, encoded);
  }

  Future<void> appendPendingPurchaseReceive(
    PendingPurchaseReceiveEntry entry,
  ) async {
    final list = await loadPendingPurchaseReceives();
    list.add(entry);
    await savePendingPurchaseReceives(list);
  }

  Future<int> countPendingPurchaseReceivesForStore(String storeId) async {
    final list = await loadPendingPurchaseReceives();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<List<PendingSaleReturnEntry>> loadPendingSaleReturns() async {
    final raw = _prefs.getString(_kPendingSaleReturnV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PendingSaleReturnEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final entry = PendingSaleReturnEntry.tryFromJson(
          Map<String, dynamic>.from(e),
        );
        if (entry != null) out.add(entry);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingSaleReturns(
    List<PendingSaleReturnEntry> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kPendingSaleReturnV1, encoded);
  }

  Future<void> appendPendingSaleReturn(PendingSaleReturnEntry entry) async {
    final list = await loadPendingSaleReturns();
    list.add(entry);
    await savePendingSaleReturns(list);
  }

  Future<int> countPendingSaleReturnsForStore(String storeId) async {
    final list = await loadPendingSaleReturns();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<List<PendingSupplierMutationEntry>>
  loadPendingSupplierMutations() async {
    final raw = _prefs.getString(_kPendingSupplierMutationsV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PendingSupplierMutationEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final entry = PendingSupplierMutationEntry.tryFromJson(
          Map<String, dynamic>.from(e),
        );
        if (entry != null) out.add(entry);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingSupplierMutations(
    List<PendingSupplierMutationEntry> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kPendingSupplierMutationsV1, encoded);
  }

  Future<void> appendPendingSupplierMutation(
    PendingSupplierMutationEntry entry,
  ) async {
    final list = await loadPendingSupplierMutations();
    list.add(entry);
    await savePendingSupplierMutations(list);
  }

  Future<int> countPendingSupplierMutationsForStore(String storeId) async {
    final list = await loadPendingSupplierMutations();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<int> countPendingProductPhotoUploadsForStore(String storeId) async {
    final list = await loadPendingProductPhotoUploads();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<int> countPendingSyncOpsForStore(String storeId) async {
    final a = await countPendingSalesForStore(storeId);
    final b = await countPendingInventoryAdjustsForStore(storeId);
    final c = await countPendingPurchaseReceivesForStore(storeId);
    final d = await countPendingSaleReturnsForStore(storeId);
    final e = await countPendingCatalogMutationsForStore(storeId);
    final f = await countPendingSupplierMutationsForStore(storeId);
    final g = await countPendingProductPhotoUploadsForStore(storeId);
    return a + b + c + d + e + f + g;
  }

  /// Quita una operación de **todas** las colas locales por [opId].
  ///
  /// La cola del dispositivo es la que reenvía en `sync/push`; borrar filas en el
  /// servidor no evita que vuelva a aparecer hasta descartarla aquí.
  Future<bool> removePendingSyncOpByOpId(String opId) async {
    final id = opId.trim();
    if (id.isEmpty) return false;
    var removed = false;

    final sales = await loadPendingSales();
    final salesNext = sales.where((e) => e.opId != id).toList(growable: false);
    if (salesNext.length != sales.length) {
      removed = true;
      await savePendingSales(salesNext);
    }

    final adjusts = await loadPendingInventoryAdjusts();
    final adjustsNext = adjusts
        .where((e) => e.opId != id)
        .toList(growable: false);
    if (adjustsNext.length != adjusts.length) {
      removed = true;
      await savePendingInventoryAdjusts(adjustsNext);
    }

    final purchases = await loadPendingPurchaseReceives();
    final purchasesNext = purchases
        .where((e) => e.opId != id)
        .toList(growable: false);
    if (purchasesNext.length != purchases.length) {
      removed = true;
      await savePendingPurchaseReceives(purchasesNext);
    }

    final returns = await loadPendingSaleReturns();
    final returnsNext = returns
        .where((e) => e.opId != id)
        .toList(growable: false);
    if (returnsNext.length != returns.length) {
      removed = true;
      await savePendingSaleReturns(returnsNext);
    }

    final suppliers = await loadPendingSupplierMutations();
    final suppliersNext = suppliers
        .where((e) => e.opId != id)
        .toList(growable: false);
    if (suppliersNext.length != suppliers.length) {
      removed = true;
      await savePendingSupplierMutations(suppliersNext);
    }

    final catalog = await loadPendingCatalogMutations();
    final catalogNext = catalog
        .where((e) => e.opId != id)
        .toList(growable: false);
    if (catalogNext.length != catalog.length) {
      removed = true;
      await savePendingCatalogMutations(catalogNext);
    }

    return removed;
  }

  Future<List<CatalogProduct>> loadCatalogProductsCache() async {
    final raw = _prefs.getString(_kCatalogProductsCacheV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <CatalogProduct>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        out.add(CatalogProduct.fromJson(Map<String, dynamic>.from(e)));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveCatalogProductsCache(List<CatalogProduct> items) async {
    final encoded = jsonEncode(
      items
          .map(
            (e) => {
              'id': e.id,
              'sku': e.sku,
              'name': e.name,
              'barcode': e.barcode,
              'description': e.description,
              'type': e.type,
              'price': e.price,
              'cost': e.cost,
              'currency': e.currency,
              'active': e.active,
              'unit': e.unit,
              'supplierId': e.supplierId,
              'pricingMode': e.pricingMode,
              'marginPercentOverride': e.marginPercentOverride,
              'effectiveMarginPercent': e.effectiveMarginPercent,
              'marginComputedPercent': e.marginComputedPercent,
              'suggestedPrice': e.suggestedPrice,
              'imageUrl': e.imageUrl,
              'blockSaleWithoutStock': e.blockSaleWithoutStock,
            },
          )
          .toList(),
    );
    await _prefs.setString(_kCatalogProductsCacheV1, encoded);
  }

  /// Reemplaza o agrega productos en la caché local sin borrar el resto (p. ej. tras PATCH en recepción).
  ///
  /// Si la caché está vacía no escribe nada: evita guardar un catálogo parcial antes del primer sync completo.
  Future<void> upsertCatalogProductsInCache(
    Iterable<CatalogProduct> updates,
  ) async {
    final list = updates.toList();
    if (list.isEmpty) return;
    final current = await loadCatalogProductsCache();
    if (current.isEmpty) return;
    final byId = <String, CatalogProduct>{for (final p in list) p.id: p};
    final merged = <CatalogProduct>[];
    for (final e in current) {
      merged.add(byId.remove(e.id) ?? e);
    }
    merged.addAll(byId.values);
    await saveCatalogProductsCache(merged);
  }

  Future<List<PendingCatalogMutationEntry>>
  loadPendingCatalogMutations() async {
    final raw = _prefs.getString(_kPendingCatalogMutationsV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <PendingCatalogMutationEntry>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final x = PendingCatalogMutationEntry.tryFromJson(
          Map<String, dynamic>.from(e),
        );
        if (x != null) out.add(x);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> savePendingCatalogMutations(
    List<PendingCatalogMutationEntry> items,
  ) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kPendingCatalogMutationsV1, encoded);
  }

  Future<void> appendPendingCatalogMutation(
    PendingCatalogMutationEntry entry,
  ) async {
    final list = await loadPendingCatalogMutations();
    list.add(entry);
    await savePendingCatalogMutations(list);
  }

  Future<int> countPendingCatalogMutationsForStore(String storeId) async {
    final list = await loadPendingCatalogMutations();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<void> saveBusinessSettingsCache(
    String storeId,
    Map<String, dynamic> raw,
  ) async {
    await _prefs.setString(
      '$_kBusinessSettingsCachePrefix${storeId.trim()}',
      jsonEncode(raw),
    );
  }

  Future<BusinessSettings?> loadBusinessSettingsCache(String storeId) async {
    final raw = _prefs.getString(
      '$_kBusinessSettingsCachePrefix${storeId.trim()}',
    );
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return BusinessSettings.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> savePosFxPairCache({
    required String storeId,
    required String functionalCode,
    required String documentCode,
    required SaleFxPair pair,
  }) async {
    final key =
        '$_kPosFxPairCachePrefix${storeId.trim()}_${functionalCode.toUpperCase()}_${documentCode.toUpperCase()}';
    final encoded = jsonEncode({
      'inverted': pair.inverted,
      'rate': {
        'id': pair.rate.id,
        'storeId': pair.rate.storeId,
        'baseCurrencyCode': pair.rate.baseCurrencyCode,
        'quoteCurrencyCode': pair.rate.quoteCurrencyCode,
        'rateQuotePerBase': pair.rate.rateQuotePerBase,
        'effectiveDate': pair.rate.effectiveDate,
        'source': pair.rate.source,
        'notes': pair.rate.notes,
        'createdAt': pair.rate.createdAt,
        'convention': pair.rate.convention,
      },
    });
    await _prefs.setString(key, encoded);
  }

  Future<SaleFxPair?> loadPosFxPairCache({
    required String storeId,
    required String functionalCode,
    required String documentCode,
  }) async {
    final key =
        '$_kPosFxPairCachePrefix${storeId.trim()}_${functionalCode.toUpperCase()}_${documentCode.toUpperCase()}';
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final rateRaw = decoded['rate'];
      if (rateRaw is! Map) return null;
      final rate = LatestExchangeRate.fromJson(
        Map<String, dynamic>.from(rateRaw),
      );
      final inverted = decoded['inverted'] == true;
      return SaleFxPair(rate: rate, inverted: inverted);
    } catch (_) {
      return null;
    }
  }

  /// Cuando en Inicio consultás/registrás una tasa, actualiza la misma clave que el POS usa offline
  /// (`funcional` → `moneda documento` de la tienda en caché), si el par coincide con lo obtenido.
  Future<void> syncPosFxPairCacheFromFetchedRate({
    required String storeId,
    required String fetchedBase,
    required String fetchedQuote,
    required LatestExchangeRate rate,
  }) async {
    final settings = await loadBusinessSettingsCache(storeId);
    if (settings == null) return;
    final func = settings.functionalCurrency.code.trim();
    final doc = (settings.defaultSaleDocCurrency?.code ?? func).trim();
    if (func.toUpperCase() == doc.toUpperCase()) return;

    final b = fetchedBase.trim().toUpperCase();
    final q = fetchedQuote.trim().toUpperCase();
    final fu = func.toUpperCase();
    final du = doc.toUpperCase();

    if (b == fu && q == du) {
      await savePosFxPairCache(
        storeId: storeId,
        functionalCode: func,
        documentCode: doc,
        pair: SaleFxPair(rate: rate, inverted: false),
      );
      return;
    }
    if (b == du && q == fu) {
      await savePosFxPairCache(
        storeId: storeId,
        functionalCode: func,
        documentCode: doc,
        pair: SaleFxPair(rate: rate, inverted: true),
      );
    }
  }

  Future<void> saveInventoryCache(
    String storeId,
    List<InventoryLine> items,
  ) async {
    final encoded = jsonEncode(
      items.map((e) {
        return {
          'id': e.id,
          'productId': e.productId,
          'quantity': e.quantity,
          'reserved': e.reserved,
          'minStock': e.minStock,
          'averageUnitCostFunctional': e.averageUnitCostFunctional,
          'totalCostFunctional': e.totalCostFunctional,
          'product': e.product == null
              ? null
              : {
                  'id': e.product!.id,
                  'sku': e.product!.sku,
                  'name': e.product!.name,
                  'barcode': e.product!.barcode,
                },
        };
      }).toList(),
    );
    await _prefs.setString('$_kInventoryCachePrefix${storeId.trim()}', encoded);
  }

  Future<List<InventoryLine>> loadInventoryCache(String storeId) async {
    final raw = _prefs.getString('$_kInventoryCachePrefix${storeId.trim()}');
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <InventoryLine>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        out.add(InventoryLine.fromJson(Map<String, dynamic>.from(e)));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Baja stock estimado local tras confirmar una venta en el dispositivo.
  /// Puede quedar negativo. Si no hay cache de inventario, no hace nada.
  Future<void> applyLocalInventoryDecrements({
    required String storeId,
    required Map<String, double> soldByProductId,
  }) async {
    if (soldByProductId.isEmpty) return;
    final lines = await loadInventoryCache(storeId);
    if (lines.isEmpty) return;
    var changed = false;
    final next = <InventoryLine>[];
    for (final line in lines) {
      final sold = soldByProductId[line.productId];
      if (sold == null || sold == 0) {
        next.add(line);
        continue;
      }
      changed = true;
      final q = (line.quantityAsDouble ?? 0) - sold;
      String qtyStr;
      if (q == q.roundToDouble()) {
        qtyStr = '${q.round()}';
      } else {
        qtyStr = q.toStringAsFixed(4);
        while (qtyStr.contains('.') &&
            (qtyStr.endsWith('0') || qtyStr.endsWith('.'))) {
          qtyStr = qtyStr.substring(0, qtyStr.length - 1);
        }
      }
      next.add(
        InventoryLine(
          id: line.id,
          productId: line.productId,
          quantity: qtyStr.isEmpty ? '0' : qtyStr,
          reserved: line.reserved,
          minStock: line.minStock,
          averageUnitCostFunctional: line.averageUnitCostFunctional,
          totalCostFunctional: line.totalCostFunctional,
          product: line.product,
        ),
      );
    }
    if (changed) await saveInventoryCache(storeId, next);
  }

  Future<void> saveSalesGeneralCache(
    String storeId, {
    required List<SalesListItem> rows,
    SalesListMeta? meta,
    required String dateFrom,
    required String dateTo,
    required bool onlyThisDevice,
  }) async {
    final encoded = jsonEncode({
      'dateFrom': dateFrom,
      'dateTo': dateTo,
      'onlyThisDevice': onlyThisDevice,
      'rows': rows
          .map(
            (r) => {
              'id': r.id,
              'createdAt': r.createdAt,
              'documentCurrencyCode': r.documentCurrencyCode,
              'totalDocument': r.totalDocument,
              'totalFunctional': r.totalFunctional,
              'deviceId': r.deviceId,
              'status': r.status,
            },
          )
          .toList(),
      'meta': meta == null
          ? null
          : {
              'timezone': meta.timezone,
              'dateFrom': meta.dateFrom,
              'dateTo': meta.dateTo,
              'rangeInterpretation': meta.rangeInterpretation,
              'limit': meta.limit,
              'hasMore': meta.hasMore,
              'deviceIdFilter': meta.deviceIdFilter,
            },
    });
    await _prefs.setString(
      '$_kSalesGeneralCachePrefix${storeId.trim()}',
      encoded,
    );
  }

  Future<
    ({
      List<SalesListItem> rows,
      SalesListMeta? meta,
      String? dateFrom,
      String? dateTo,
      bool? onlyThisDevice,
    })?
  >
  loadSalesGeneralCache(String storeId) async {
    final raw = _prefs.getString('$_kSalesGeneralCachePrefix${storeId.trim()}');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final rowsRaw = map['rows'];
      final rows = <SalesListItem>[];
      if (rowsRaw is List) {
        for (final e in rowsRaw) {
          if (e is! Map) continue;
          final it = SalesListItem.tryFromJson(Map<String, dynamic>.from(e));
          if (it != null) rows.add(it);
        }
      }
      SalesListMeta? meta;
      final metaRaw = map['meta'];
      if (metaRaw is Map) {
        meta = SalesListMeta.tryFromJson(Map<String, dynamic>.from(metaRaw));
      }
      return (
        rows: rows,
        meta: meta,
        dateFrom: map['dateFrom']?.toString(),
        dateTo: map['dateTo']?.toString(),
        onlyThisDevice: map['onlyThisDevice'] is bool
            ? map['onlyThisDevice'] as bool
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLatestRateCache({
    required String storeId,
    required String baseCurrencyCode,
    required String quoteCurrencyCode,
    String? effectiveOn,
    required LatestExchangeRate rate,
  }) async {
    final key =
        '$_kLatestRateCachePrefix${storeId.trim()}_${baseCurrencyCode.toUpperCase()}_${quoteCurrencyCode.toUpperCase()}_${(effectiveOn ?? '').trim()}';
    final encoded = jsonEncode({
      'id': rate.id,
      'storeId': rate.storeId,
      'baseCurrencyCode': rate.baseCurrencyCode,
      'quoteCurrencyCode': rate.quoteCurrencyCode,
      'rateQuotePerBase': rate.rateQuotePerBase,
      'effectiveDate': rate.effectiveDate,
      'source': rate.source,
      'notes': rate.notes,
      'createdAt': rate.createdAt,
      'convention': rate.convention,
    });
    await _prefs.setString(key, encoded);
  }

  Future<LatestExchangeRate?> loadLatestRateCache({
    required String storeId,
    required String baseCurrencyCode,
    required String quoteCurrencyCode,
    String? effectiveOn,
  }) async {
    final key =
        '$_kLatestRateCachePrefix${storeId.trim()}_${baseCurrencyCode.toUpperCase()}_${quoteCurrencyCode.toUpperCase()}_${(effectiveOn ?? '').trim()}';
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return LatestExchangeRate.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// Tickets en espera (ON_HOLD) — **no** van a `pending_sales` ni sync hasta cobrar.
  Future<List<HeldTicket>> loadHeldTickets() async {
    final raw = _prefs.getString(_kHeldTicketsV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <HeldTicket>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final t = HeldTicket.tryFromJson(Map<String, dynamic>.from(e));
        if (t != null) out.add(t);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveHeldTickets(List<HeldTicket> items) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kHeldTicketsV1, encoded);
  }

  /// Lista filtrada por tienda y dispositivo (misma política que el doc §6).
  Future<List<HeldTicket>> listHeldTicketsForStoreAndDevice({
    required String storeId,
    required String deviceId,
  }) async {
    final all = await loadHeldTickets();
    return all
        .where(
          (t) =>
              t.storeId == storeId &&
              t.deviceId == deviceId &&
              t.status == HeldTicket.statusOnHold,
        )
        .toList()
      ..sort((a, b) => b.updatedAtIso.compareTo(a.updatedAtIso));
  }

  Future<void> upsertHeldTicket(HeldTicket ticket) async {
    final list = await loadHeldTickets();
    list.removeWhere((t) => t.id == ticket.id);
    list.add(ticket);
    await saveHeldTickets(list);
  }

  Future<void> deleteHeldTicket(String id) async {
    final list = await loadHeldTickets();
    list.removeWhere((t) => t.id == id);
    await saveHeldTickets(list);
  }

  Future<void> updateHeldTicketAlias({
    required String id,
    required String? alias,
  }) async {
    final list = await loadHeldTickets();
    final i = list.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final old = list[i];
    list[i] = HeldTicket(
      id: old.id,
      storeId: old.storeId,
      deviceId: old.deviceId,
      status: old.status,
      alias: alias,
      note: old.note,
      documentCurrencyCode: old.documentCurrencyCode,
      fxSnapshot: old.fxSnapshot,
      totals: old.totals,
      lines: old.lines,
      createdAtIso: old.createdAtIso,
      updatedAtIso: DateTime.now().toUtc().toIso8601String(),
      heldByUserId: old.heldByUserId,
    );
    await saveHeldTickets(list);
  }

  Future<int> countHeldTicketsForStoreAndDevice({
    required String storeId,
    required String deviceId,
  }) async {
    final list = await listHeldTicketsForStoreAndDevice(
      storeId: storeId,
      deviceId: deviceId,
    );
    return list.length;
  }

  String _activePosCartKey(String storeId, String deviceId) =>
      '$_kActivePosCartPrefix${storeId}_$deviceId';

  /// Ticket activo del POS (no es “en espera” ni cola de sync).
  Future<ActivePosCartDraft?> loadActivePosCartDraft({
    required String storeId,
    required String deviceId,
  }) async {
    final raw = _prefs.getString(_activePosCartKey(storeId, deviceId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final draft = ActivePosCartDraft.tryFromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (draft == null) return null;
      if (draft.storeId != storeId || draft.deviceId != deviceId) return null;
      return draft;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActivePosCartDraft(ActivePosCartDraft draft) async {
    await _prefs.setString(
      _activePosCartKey(draft.storeId, draft.deviceId),
      jsonEncode(draft.toJson()),
    );
  }

  Future<void> clearActivePosCartDraft({
    required String storeId,
    required String deviceId,
  }) async {
    await _prefs.remove(_activePosCartKey(storeId, deviceId));
  }

  String _localCashSessionKey(String storeId, String deviceId) =>
      '$_kLocalCashSessionPrefix${storeId}_$deviceId';

  Future<LocalCashSession?> loadLocalCashSession({
    required String storeId,
    required String deviceId,
  }) async {
    final raw = _prefs.getString(_localCashSessionKey(storeId, deviceId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final s = LocalCashSession.tryFromJson(Map<String, dynamic>.from(decoded));
      if (s == null) return null;
      if (s.storeId != storeId || s.deviceId != deviceId) return null;
      return s;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLocalCashSession(LocalCashSession session) async {
    await _prefs.setString(
      _localCashSessionKey(session.storeId, session.deviceId),
      jsonEncode(session.toJson()),
    );
  }

  Future<void> clearLocalCashSession({
    required String storeId,
    required String deviceId,
  }) async {
    await _prefs.remove(_localCashSessionKey(storeId, deviceId));
  }

  /// Historial local de tickets: **hoy y ayer** (calendario local del dispositivo); al cargar se purgan entradas más viejas.
  /// Máx. ~80 filas para no inflar preferencias. Filtrar por tienda en UI.
  Future<List<RecentSaleTicket>> loadRecentSaleTickets() async {
    final raw = _prefs.getString(_kRecentSalesV1);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <RecentSaleTicket>[];
      for (final e in decoded) {
        if (e is! Map) continue;
        final t = RecentSaleTicket.tryFromJson(Map<String, dynamic>.from(e));
        if (t != null) out.add(t);
      }
      final windowed = out
          .where((t) => t.isRecordedOnLocalDeviceHistoryWindow)
          .toList();
      if (windowed.length != out.length) {
        await saveRecentSaleTickets(windowed);
      }
      return windowed;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecentSaleTickets(List<RecentSaleTicket> items) async {
    final encoded = jsonEncode(items.map((e) => e.toJson()).toList());
    await _prefs.setString(_kRecentSalesV1, encoded);
  }

  static const _kMaxRecentSalesSameDay = 80;

  /// Número de ticket local del día (5 dígitos, reinicia cada día calendario local).
  Future<String> allocateLocalTicketDisplayCode() async {
    final now = DateTime.now();
    final ymd =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    Map<String, dynamic> state = {};
    final raw = _prefs.getString(_kTicketDisplaySeqStateV1);
    if (raw != null && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) state = Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    var seq = 1;
    if (state['ymd']?.toString() == ymd) {
      final n = state['next'];
      if (n is int) {
        seq = n;
      } else if (n is num) {
        seq = n.toInt();
      }
    }
    if (seq < 1 || seq > 99999) seq = 1;
    final code = seq.toString().padLeft(5, '0');
    final nextSeq = seq >= 99999 ? 1 : seq + 1;
    await _prefs.setString(
      _kTicketDisplaySeqStateV1,
      jsonEncode({'ymd': ymd, 'next': nextSeq}),
    );
    return code;
  }

  /// Si ya no hay venta en cola local con ese [clientSaleId], el ticket no debería seguir como "pendiente".
  Future<void> reconcileRecentQueuedTicketsWithPendingSales(
    String storeId,
  ) async {
    final pending = await loadPendingSales();
    final pendingSaleIds = <String>{};
    for (final e in pending) {
      if (e.storeId != storeId) continue;
      final id = e.sale['id']?.toString();
      if (id != null && id.isNotEmpty) pendingSaleIds.add(id);
    }
    final list = await loadRecentSaleTickets();
    var changed = false;
    final out = <RecentSaleTicket>[];
    for (final t in list) {
      if (t.storeId == storeId &&
          t.status == RecentSaleTicket.statusQueued &&
          !pendingSaleIds.contains(t.saleId)) {
        changed = true;
        out.add(t.copyWith(status: RecentSaleTicket.statusSynced));
      } else {
        out.add(t);
      }
    }
    if (changed) await saveRecentSaleTickets(out);
  }

  /// Tras `sync/push` con ack de una venta offline: dejar de mostrar "pendiente" en historial local.
  Future<void> markRecentSaleTicketSyncedByClientId(String clientSaleId) async {
    if (clientSaleId.isEmpty) return;
    final list = await loadRecentSaleTickets();
    var changed = false;
    final out = <RecentSaleTicket>[];
    for (final t in list) {
      if (t.saleId == clientSaleId &&
          t.status == RecentSaleTicket.statusQueued) {
        changed = true;
        out.add(t.copyWith(status: RecentSaleTicket.statusSynced));
      } else {
        out.add(t);
      }
    }
    if (changed) await saveRecentSaleTickets(out);
  }

  /// Tras devolución/anulación exitosa: no contar en cierre local.
  Future<void> markRecentSaleTicketReturned(String saleId) async {
    if (saleId.isEmpty) return;
    final list = await loadRecentSaleTickets();
    var changed = false;
    final out = <RecentSaleTicket>[];
    for (final t in list) {
      if (t.saleId == saleId &&
          t.status != RecentSaleTicket.statusReturned) {
        changed = true;
        out.add(t.copyWith(status: RecentSaleTicket.statusReturned));
      } else {
        out.add(t);
      }
    }
    if (changed) await saveRecentSaleTickets(out);
  }

  /// Busca en historial **de hoy** de este dispositivo por número corto (4–5 dígitos con o sin ceros).
  Future<RecentSaleTicket?> findRecentSaleTicketByDisplayCode(
    String storeId,
    String userCode,
  ) async {
    final list = await loadRecentSaleTickets();
    for (final t in list) {
      if (t.storeId != storeId) continue;
      if (RecentSaleTicket.displayCodeMatches(t.displayCode, userCode)) {
        return t;
      }
    }
    return null;
  }

  /// Inserta al frente; solo ventas de **hoy o ayer** (calendario local); evita duplicar [saleId].
  Future<void> prependRecentSaleTicket(RecentSaleTicket entry) async {
    final list = await loadRecentSaleTickets();
    final next = <RecentSaleTicket>[];
    if (entry.isRecordedOnLocalDeviceHistoryWindow) {
      next.add(entry);
    }
    for (final e in list) {
      if (e.saleId == entry.saleId) continue;
      if (!e.isRecordedOnLocalDeviceHistoryWindow) continue;
      next.add(e);
      if (next.length >= _kMaxRecentSalesSameDay) break;
    }
    await saveRecentSaleTickets(next);
  }

  Future<void> saveDashboardAccessToken(String deviceId, String token) async {
    await _prefs.setString(
      '$_kDashboardAccessTokenPrefix${deviceId.trim()}',
      token.trim(),
    );
  }

  Future<String?> getDashboardAccessToken(String deviceId) async {
    final v = _prefs.getString('$_kDashboardAccessTokenPrefix${deviceId.trim()}');
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> clearDashboardAccessToken(String deviceId) async {
    await _prefs.remove('$_kDashboardAccessTokenPrefix${deviceId.trim()}');
  }

  Future<void> saveDashboardKioskCache(String deviceId, String json) async {
    await _prefs.setString(
      '$_kDashboardKioskCachePrefix${deviceId.trim()}',
      json,
    );
  }

  Future<String?> loadDashboardKioskCache(String deviceId) async {
    return _prefs.getString('$_kDashboardKioskCachePrefix${deviceId.trim()}');
  }

  Future<void> saveCachedDeviceMode(String mode) async {
    await _prefs.setString(_kCachedDeviceModeV1, mode.trim());
  }

  Future<String?> getCachedDeviceMode() async {
    final v = _prefs.getString(_kCachedDeviceModeV1);
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> saveCachedDashboardEnabled(String deviceId, bool enabled) async {
    await _prefs.setBool(
      '$_kCachedDashboardEnabledPrefix${deviceId.trim()}',
      enabled,
    );
  }

  Future<bool?> getCachedDashboardEnabled(String deviceId) async {
    final key = '$_kCachedDashboardEnabledPrefix${deviceId.trim()}';
    if (!_prefs.containsKey(key)) return null;
    return _prefs.getBool(key);
  }

  String _deviceModuleKey(String prefix, String storeId, String deviceId) =>
      '$prefix${storeId.trim()}_${deviceId.trim()}';

  /// Si nunca se configuró → `false` (bloqueado hasta habilitar con PIN).
  Future<bool> isInventoryModuleEnabled({
    required String storeId,
    required String deviceId,
  }) async {
    final key = _deviceModuleKey(
      _kDeviceModuleInventoryPrefix,
      storeId,
      deviceId,
    );
    if (!_prefs.containsKey(key)) return false;
    return _prefs.getBool(key) ?? false;
  }

  Future<void> setInventoryModuleEnabled({
    required String storeId,
    required String deviceId,
    required bool enabled,
  }) async {
    await _prefs.setBool(
      _deviceModuleKey(_kDeviceModuleInventoryPrefix, storeId, deviceId),
      enabled,
    );
  }

  /// Si nunca se configuró → `false` (bloqueado hasta habilitar con PIN).
  Future<bool> isSuppliersModuleEnabled({
    required String storeId,
    required String deviceId,
  }) async {
    final key = _deviceModuleKey(
      _kDeviceModuleSuppliersPrefix,
      storeId,
      deviceId,
    );
    if (!_prefs.containsKey(key)) return false;
    return _prefs.getBool(key) ?? false;
  }

  Future<void> setSuppliersModuleEnabled({
    required String storeId,
    required String deviceId,
    required bool enabled,
  }) async {
    await _prefs.setBool(
      _deviceModuleKey(_kDeviceModuleSuppliersPrefix, storeId, deviceId),
      enabled,
    );
  }
}
