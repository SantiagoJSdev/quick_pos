import '../config/app_config.dart';

/// Cabeceras para túneles ngrok free (evita página intersticial HTML).
Map<String, String> ngrokSkipBrowserWarningHeadersForApiBase(String apiV1Base) {
  final u = Uri.tryParse(AppConfig.normalizeApiBaseUrl(apiV1Base));
  if (u == null) return const {};
  final host = u.host;
  if (host.contains('ngrok-free.') || host.contains('ngrok-free.app')) {
    return const {'ngrok-skip-browser-warning': 'true'};
  }
  return const {};
}
