import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/local_supplier.dart';
import '../sync/pending_inventory_adjust_entry.dart';
import '../sync/pending_sale_entry.dart';

const _kStoreId = 'store_id';
const _kDeviceId = 'device_id';
const _kLocalSuppliers = 'local_suppliers_v1';
const _kPendingSalesV1 = 'pending_sales_v1';
const _kPendingInvAdjustV1 = 'pending_inventory_adjusts_v1';
const _kSyncPullSinceV1 = 'sync_pull_since_v1';

class LocalPrefs {
  LocalPrefs(this._prefs);

  final SharedPreferences _prefs;
  static const _uuid = Uuid();

  Future<String?> getStoreId() async => _prefs.getString(_kStoreId);

  Future<void> setStoreId(String storeId) =>
      _prefs.setString(_kStoreId, storeId.trim());

  Future<void> clearStoreId() => _prefs.remove(_kStoreId);

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

  Future<int> countPendingSyncOpsForStore(String storeId) async {
    final a = await countPendingSalesForStore(storeId);
    final b = await countPendingInventoryAdjustsForStore(storeId);
    return a + b;
  }
}
