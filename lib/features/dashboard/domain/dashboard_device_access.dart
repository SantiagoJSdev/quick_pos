import 'device_dashboard_config.dart';

/// Reglas de visibilidad por dispositivo (`GET/PATCH .../dashboard-config`).
class DashboardDeviceAccess {
  DashboardDeviceAccess._();

  /// Tablero dentro del POS (botón en Inicio). Requiere flag del servidor.
  static bool showsOperationalDashboard(DeviceDashboardConfig config) {
    if (!config.dashboardEnabled) return false;
    // Modo TV pantalla completa: no duplicar entrada en Inicio.
    return config.deviceMode != DeviceMode.dashboard;
  }

  /// Arranque directo en pantalla TV/kiosk.
  static bool showsKioskAtStartup(DeviceDashboardConfig config) {
    return config.dashboardEnabled &&
        config.deviceMode == DeviceMode.dashboard &&
        config.hasDashboardToken;
  }
}
