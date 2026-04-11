import 'package:connectivity_plus/connectivity_plus.dart';

import '../api/api_client.dart';
import '../api/stores_api.dart';
import '../config/app_config.dart';
import '../storage/local_prefs.dart';
import 'backend_origin_resolver.dart';
import 'connectivity_util.dart';

/// Cuando el backend no responde y la URL la gestiona el resolver (Vercel + ngrok),
/// intenta leer un origen nuevo, probar y aplicar [AppConfig] + prefs.
///
/// No hace nada si el usuario fijó URL manual (sin seguir la nube).
Future<bool> tryRefreshApiBaseFromCloudWhenUnreachable({
  required LocalPrefs prefs,
  required String storeId,
}) async {
  if (!await prefs.getApiBaseFollowsCloudResolver()) return false;

  List<ConnectivityResult> conn;
  try {
    conn = await Connectivity().checkConnectivity();
  } catch (_) {
    return false;
  }
  if (!connectivityAppearsOnline(conn)) return false;

  final resolver = BackendOriginResolver();
  final vercel = await resolver.fetchFromVercel();
  if (vercel != null) {
    await prefs.setPersistedApiOrigin(vercel.baseUrl, vercel.updatedAt);
  }

  final origin =
      vercel?.baseUrl ?? await prefs.getPersistedApiOrigin();
  if (origin == null || origin.isEmpty) return false;

  final apiV1 = apiV1BaseFromOrigin(origin);
  if (apiV1.isEmpty) return false;

  final normalizedNew = AppConfig.normalizeApiBaseUrl(apiV1);
  final stored = await prefs.getApiBaseUrlOverride();
  final currentNorm = AppConfig.normalizeApiBaseUrl(
    stored ?? AppConfig.effectiveApiBaseUrl,
  );
  if (normalizedNew == currentNorm) return false;

  final sid = storeId.trim();
  if (sid.isEmpty) return false;

  final c = ApiClient(baseUrl: normalizedNew);
  try {
    await StoresApi(c).getBusinessSettings(sid);
  } catch (_) {
    return false;
  } finally {
    c.close();
  }

  await prefs.setApiBaseUrlOverride(
    normalizedNew,
    followCloudResolver: true,
  );
  AppConfig.setRuntimeApiBaseUrlOverride(normalizedNew);
  return true;
}
