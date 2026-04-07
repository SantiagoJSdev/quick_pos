/// Base URL del API **sin** barra final (ej. `http://10.0.2.2:3002/api/v1`).
/// Emulador Android → `localhost` del PC es `10.0.2.2`.
///
/// Override al ejecutar:
/// `flutter run --dart-define=API_BASE_URL=https://mi-servidor.com/api/v1`
///
/// Clave para **Inicio → Configuración (clave)** (margen de tienda, id tienda), hasta haber usuarios/roles.
///
/// Por defecto en código: [defaultAdminPin]. Solo si al compilar pasás un valor **no vacío**:
/// `flutter run --dart-define=CONFIG_ADMIN_PIN=otra_clave`
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.0.190:3002/api/v1',
  );
  //  defaultValue: 'http://10.0.2.2:3002/api/v1',

  /// PIN que acepta la app sin configurar nada al compilar ni al ejecutar.
  static const String defaultAdminPin = '1200Mia';

  /// Sobrescritura opcional al compilar. Si falta o está vacío → [defaultAdminPin].
  static const String _configAdminPinOverride = String.fromEnvironment(
    'CONFIG_ADMIN_PIN',
    defaultValue: '',
  );

  /// Clave que usa el diálogo de configuración.
  static String get effectiveConfigAdminPin {
    final o = _configAdminPinOverride.trim();
    return o.isEmpty ? defaultAdminPin : o;
  }

  /// Comparación con la clave esperada (misma cadena o misma sin importar mayúsculas).
  static bool adminPinMatches(String entered) {
    final e = entered.trim();
    if (e.isEmpty) return false;
    final p = effectiveConfigAdminPin;
    return e == p || e.toLowerCase() == p.toLowerCase();
  }
}
