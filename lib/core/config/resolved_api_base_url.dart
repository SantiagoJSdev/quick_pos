import '../storage/local_prefs.dart';
import 'app_config.dart';

/// Carga en [AppConfig] la URL base del API (`…/api/v1`) que usará [ApiClient].
///
/// Orden: **override guardado en el dispositivo** (Configuración con clave), si no hay,
/// **valor de compilación** [AppConfig.apiBaseUrl] (`API_BASE_URL` / default).
Future<String> loadResolvedApiBaseUrl(LocalPrefs prefs) async {
  final saved = await prefs.getApiBaseUrlOverride();
  final fromDisk = AppConfig.normalizeApiBaseUrl(saved ?? '');
  final resolved = fromDisk.isNotEmpty
      ? fromDisk
      : AppConfig.normalizeApiBaseUrl(AppConfig.apiBaseUrl);
  AppConfig.setRuntimeApiBaseUrlOverride(resolved);
  return resolved;
}
