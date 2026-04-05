import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/local_supplier.dart';

const _kStoreId = 'store_id';
const _kDeviceId = 'device_id';
const _kLocalSuppliers = 'local_suppliers_v1';

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
}
