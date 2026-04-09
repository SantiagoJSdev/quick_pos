import '../config/app_config.dart';

/// Convierte [raw] del backend en URL usable en el cliente (emulador: `localhost` → host del API).
String? resolveProductImageUrl(String? raw) {
  final s = raw?.trim() ?? '';
  if (s.isEmpty) return null;
  var u = Uri.tryParse(s);
  if (u != null && u.hasScheme) {
    final host = u.host.toLowerCase();
    if (host == 'localhost' || host == '127.0.0.1') {
      final api = Uri.parse(AppConfig.effectiveApiBaseUrl);
      final path = u.path;
      final q = u.hasQuery ? '?${u.query}' : '';
      return '${api.origin}$path$q';
    }
    return s;
  }
  final base = AppConfig.effectiveApiBaseUrl;
  if (s.startsWith('/')) {
    final root = Uri.parse(base).origin;
    return '$root$s';
  }
  return '$base/$s';
}
