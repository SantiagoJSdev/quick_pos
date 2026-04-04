/// Base URL del API **sin** barra final (ej. `http://10.0.2.2:3000/api/v1`).
/// Emulador Android → `localhost` del PC es `10.0.2.2`.
///
/// Override al ejecutar:
/// `flutter run --dart-define=API_BASE_URL=https://mi-servidor.com/api/v1`
class AppConfig {
  AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
}
