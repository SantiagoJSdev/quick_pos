import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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

const _kStoreId = 'store_id';
const _kDeviceId = 'device_id';
const _kLocalSuppliers = 'local_suppliers_v1';
const _kPendingSalesV1 = 'pending_sales_v1';
const _kPendingInvAdjustV1 = 'pending_inventory_adjusts_v1';
const _kPendingPurchaseReceiveV1 = 'pending_purchase_receive_v1';
const _kPendingSaleReturnV1 = 'pending_sale_return_v1';
const _kSyncPullSinceV1 = 'sync_pull_since_v1';
const _kRecentSalesV1 = 'recent_sales_v1';
const _kTicketDisplaySeqStateV1 = 'ticket_display_seq_state_v1';
const _kHeldTicketsV1 = 'held_tickets_v1';
const _kCatalogProductsCacheV1 = 'catalog_products_cache_v1';
const _kPendingCatalogMutationsV1 = 'pending_catalog_mutations_v1';
const _kBusinessSettingsCachePrefix = 'business_settings_cache_v1_';
const _kPosFxPairCachePrefix = 'pos_fx_pair_cache_v1_';
const _kInventoryCachePrefix = 'inventory_cache_v1_';
const _kSalesGeneralCachePrefix = 'sales_general_cache_v1_';
const _kLatestRateCachePrefix = 'latest_rate_cache_v1_';
const _kApiBaseUrlOverrideV1 = 'api_base_url_override_v1';
const _kApiFollowCloudResolverV1 = 'api_follow_cloud_resolver_v1';
const _kPosApiOrigin = 'pos_api_origin';
const _kPosApiOriginUpdatedAt = 'pos_api_origin_updated_at';
const _kPendingProductPhotoUploadsV1 = 'pending_product_photo_uploads_v1';

class LocalPrefs {
  LocalPrefs(this._prefs);

  final SharedPreferences _prefs;
  static const _uuid = Uuid();

  Future<String?> getStoreId() async => _prefs.getString(_kStoreId);

  Future<void> setStoreId(String storeId) =>
      _prefs.setString(_kStoreId, storeId.trim());

  Future<void> clearStoreId() => _prefs.remove(_kStoreId);

  Future<String?> getApiBaseUrlOverride() async {
    final raw = _prefs.getString(_kApiBaseUrlOverrideV1);
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// [followCloudResolver]: si es `true`, [MainShell] puede actualizar la URL desde Vercel en segundo plano
  /// cuando el backend no responde (túnel ngrok nuevo). Manual / «Usar default» → `false`.
  Future<void> setApiBaseUrlOverride(
    String url, {
    required bool followCloudResolver,
  }) async {
    await _prefs.setString(_kApiBaseUrlOverrideV1, url.trim());
    await _prefs.setBool(_kApiFollowCloudResolverV1, followCloudResolver);
  }

  Future<bool> getApiBaseFollowsCloudResolver() async =>
      _prefs.getBool(_kApiFollowCloudResolverV1) ?? false;

  Future<void> clearApiBaseUrlOverride() async {
    await _prefs.remove(_kApiBaseUrlOverrideV1);
    await _prefs.remove(_kApiFollowCloudResolverV1);
  }

  /// Origen del API sin path (p. ej. `https://….ngrok-free.dev`). Solo “último conocido” del resolver.
  Future<void> setPersistedApiOrigin(String origin, DateTime? updatedAt) async {
    final o = origin.trim().replaceAll(RegExp(r'/+$'), '');
    if (o.isEmpty) {
      await _prefs.remove(_kPosApiOrigin);
      await _prefs.remove(_kPosApiOriginUpdatedAt);
      return;
    }
    await _prefs.setString(_kPosApiOrigin, o);
    if (updatedAt != null) {
      await _prefs.setString(
        _kPosApiOriginUpdatedAt,
        updatedAt.toUtc().toIso8601String(),
      );
    }
  }

  Future<String?> getPersistedApiOrigin() async {
    final s = _prefs.getString(_kPosApiOrigin)?.trim();
    if (s == null || s.isEmpty) return null;
    return s;
  }

  Future<DateTime?> getPersistedApiOriginUpdatedAt() async {
    final s = _prefs.getString(_kPosApiOriginUpdatedAt);
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  Future<List<PendingProductPhotoUploadEntry>> loadPendingProductPhotoUploads() async {
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
    list.add(entry);
    await savePendingSales(list);
  }

  Future<int> countPendingSalesForStore(String storeId) async {
    final list = await loadPendingSales();
    return list.where((e) => e.storeId == storeId).length;
  }

  Future<List<PendingInventoryAdjustEntry>> loadPendingInventoryAdjusts() async {
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

  Future<List<PendingPurchaseReceiveEntry>> loadPendingPurchaseReceives() async {
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

  Future<void> savePendingSaleReturns(List<PendingSaleReturnEntry> items) async {
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

  Future<int> countPendingSyncOpsForStore(String storeId) async {
    final a = await countPendingSalesForStore(storeId);
    final b = await countPendingInventoryAdjustsForStore(storeId);
    final c = await countPendingPurchaseReceivesForStore(storeId);
    final d = await countPendingSaleReturnsForStore(storeId);
    final e = await countPendingCatalogMutationsForStore(storeId);
    return a + b + c + d + e;
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
    final encoded = jsonEncode(items
        .map((e) => {
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
            })
        .toList());
    await _prefs.setString(_kCatalogProductsCacheV1, encoded);
  }

  Future<List<PendingCatalogMutationEntry>> loadPendingCatalogMutations() async {
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
    final raw = _prefs.getString('$_kBusinessSettingsCachePrefix${storeId.trim()}');
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
      final rate = LatestExchangeRate.fromJson(Map<String, dynamic>.from(rateRaw));
      final inverted = decoded['inverted'] == true;
      return SaleFxPair(rate: rate, inverted: inverted);
    } catch (_) {
      return null;
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
          .map((r) => {
                'id': r.id,
                'createdAt': r.createdAt,
                'documentCurrencyCode': r.documentCurrencyCode,
                'totalDocument': r.totalDocument,
                'totalFunctional': r.totalFunctional,
                'deviceId': r.deviceId,
                'status': r.status,
              })
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

  Future<({
    List<SalesListItem> rows,
    SalesListMeta? meta,
    String? dateFrom,
    String? dateTo,
    bool? onlyThisDevice
  })?> loadSalesGeneralCache(String storeId) async {
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
      final windowed =
          out.where((t) => t.isRecordedOnLocalDeviceHistoryWindow).toList();
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
  Future<void> reconcileRecentQueuedTicketsWithPendingSales(String storeId) async {
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
}
