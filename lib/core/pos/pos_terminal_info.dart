import 'package:package_info_plus/package_info_plus.dart';

import '../storage/local_prefs.dart';

/// Datos del terminal para **`POST /api/v1/sales`** y **`POST /api/v1/sync/push`**.
///
/// **Varios equipos, misma tienda:** todas las instalaciones comparten el `storeId`
/// guardado en [LocalPrefs]; cada una tiene su propio `deviceId` ([LocalPrefs.getOrCreateDeviceId]).
///
/// Contrato: `FRONTEND_INTEGRATION_CONTEXT.md` (§2 ventas, §5 sync, §8, §13.9, §13.12).
/// - `deviceId` estable por instalación; upsert `POSDevice` + enlace venta; **409** si el
///   mismo id ya está en otra tienda.
/// - `appVersion` opcional (string corto); también en el batch de `sync/push`.
class PosTerminalInfo {
  PosTerminalInfo({required this.deviceId, required this.appVersion});

  final String deviceId;
  final String appVersion;

  static Future<PosTerminalInfo> load(LocalPrefs prefs) async {
    final deviceId = await prefs.getOrCreateDeviceId();
    final pkg = await PackageInfo.fromPlatform();
    return PosTerminalInfo(
      deviceId: deviceId,
      appVersion: pkg.version,
    );
  }
}
