import '../../../core/api/api_client.dart';
import '../domain/dashboard_filters.dart';
import '../domain/dashboard_summary.dart';
import '../domain/dashboard_timeseries.dart';
import '../domain/device_dashboard_config.dart';
import '../domain/device_dashboard_payload.dart';
import '../domain/payment_breakdown_item.dart';

/// Reportes operativos y kiosk — `docs/FRONTEND_DASHBOARD_API.md`.
class DashboardApi {
  DashboardApi(this._client);

  final ApiClient _client;

  static const _reportsPrefix = '/reports/sales';

  Future<DashboardSummary> getSalesSummary(
    String storeId,
    DashboardFilters filters,
  ) async {
    final raw = await _client.getJson(
      '$_reportsPrefix/summary',
      storeId,
      query: filters.toQueryParams(),
    );
    return DashboardSummary.fromJson(raw);
  }

  Future<DashboardTimeSeries> getSalesTimeSeries(
    String storeId,
    DashboardFilters filters,
  ) async {
    final raw = await _client.getJson(
      '$_reportsPrefix/timeseries',
      storeId,
      query: filters.toQueryParams(),
    );
    return DashboardTimeSeries.fromJson(raw);
  }

  Future<SalesPaymentsReport> getSalesPayments(
    String storeId,
    DashboardFilters filters,
  ) async {
    final raw = await _client.getJson(
      '$_reportsPrefix/payments',
      storeId,
      query: filters.toQueryParams(),
    );
    return SalesPaymentsReport.fromJson(raw);
  }

  Future<DeviceDashboardPayload> getDeviceDashboard({
    required String deviceId,
    required String deviceToken,
    DashboardFilters filters = const DashboardFilters.today(),
  }) async {
    final raw = await _client.getJsonWithoutStore(
      '/dashboard/device/$deviceId',
      query: filters.toQueryParams(),
      headers: {'X-Device-Token': deviceToken},
    );
    return DeviceDashboardPayload.fromJson(raw);
  }

  Future<DeviceDashboardConfig> getDashboardConfig(
    String storeId,
    String deviceId,
  ) async {
    final raw = await _client.getJson(
      '/pos-devices/$deviceId/dashboard-config',
      storeId,
    );
    return DeviceDashboardConfig.fromJson(raw);
  }

  Future<DeviceDashboardConfig> patchDashboardConfig({
    required String storeId,
    required String deviceId,
    required String adminPin,
    bool? dashboardEnabled,
    DeviceMode? deviceMode,
    String? dashboardView,
    bool? regenerateToken,
  }) async {
    final body = <String, dynamic>{};
    if (dashboardEnabled != null) {
      body['dashboardEnabled'] = dashboardEnabled;
    }
    if (deviceMode != null) body['deviceMode'] = deviceMode.apiValue;
    if (dashboardView != null) body['dashboardView'] = dashboardView;
    if (regenerateToken != null) body['regenerateToken'] = regenerateToken;

    final raw = await _client.patchJson(
      '/pos-devices/$deviceId/dashboard-config',
      storeId,
      body.isEmpty ? null : body,
      extraHeaders: {'X-Dashboard-Admin-Pin': adminPin.trim()},
    );
    return DeviceDashboardConfig.fromJson(raw);
  }
}
