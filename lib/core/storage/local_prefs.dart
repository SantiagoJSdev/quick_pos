import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _kStoreId = 'store_id';
const _kDeviceId = 'device_id';

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
}
