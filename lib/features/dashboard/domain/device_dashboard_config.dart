enum DeviceMode {
  pos('POS'),
  dashboard('DASHBOARD'),
  hybrid('HYBRID');

  const DeviceMode(this.apiValue);

  final String apiValue;

  static DeviceMode? fromApi(String? raw) {
    if (raw == null) return null;
    final u = raw.trim().toUpperCase();
    for (final m in DeviceMode.values) {
      if (m.apiValue == u) return m;
    }
    return null;
  }
}

class DeviceDashboardConfig {
  const DeviceDashboardConfig({
    required this.id,
    required this.deviceId,
    required this.storeId,
    required this.dashboardEnabled,
    required this.deviceMode,
    required this.dashboardView,
    required this.hasDashboardToken,
    this.lastHeartbeatAt,
    this.lastSeen,
    this.appVersion,
    this.dashboardAccessToken,
  });

  final String id;
  final String deviceId;
  final String storeId;
  final bool dashboardEnabled;
  final DeviceMode deviceMode;
  final String dashboardView;
  final bool hasDashboardToken;
  final String? lastHeartbeatAt;
  final String? lastSeen;
  final String? appVersion;
  final String? dashboardAccessToken;

  factory DeviceDashboardConfig.fromJson(Map<String, dynamic> json) {
    return DeviceDashboardConfig(
      id: json['id']?.toString() ?? '',
      deviceId: json['deviceId']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      dashboardEnabled: json['dashboardEnabled'] == true,
      deviceMode:
          DeviceMode.fromApi(json['deviceMode']?.toString()) ?? DeviceMode.pos,
      dashboardView: json['dashboardView']?.toString() ?? 'SALES_SUMMARY',
      hasDashboardToken: json['hasDashboardToken'] == true,
      lastHeartbeatAt: json['lastHeartbeatAt']?.toString(),
      lastSeen: json['lastSeen']?.toString(),
      appVersion: json['appVersion']?.toString(),
      dashboardAccessToken: json['dashboardAccessToken']?.toString(),
    );
  }
}
