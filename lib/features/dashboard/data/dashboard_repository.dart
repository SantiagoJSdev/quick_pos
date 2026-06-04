import 'dart:convert';

import '../../../core/storage/local_prefs.dart';
import '../domain/dashboard_filters.dart';
import '../domain/dashboard_summary.dart';
import '../domain/dashboard_timeseries.dart';
import '../domain/device_dashboard_config.dart';
import '../domain/device_dashboard_payload.dart';
import '../domain/payment_breakdown_item.dart';
import 'dashboard_api.dart';

/// Estado agregado del tablero operador (3 endpoints en paralelo).
class DashboardHomeData {
  const DashboardHomeData({
    required this.summary,
    required this.timeSeries,
    required this.payments,
    required this.loadedAt,
  });

  final DashboardSummary summary;
  final DashboardTimeSeries timeSeries;
  final SalesPaymentsReport payments;
  final DateTime loadedAt;

  String get periodLabel => '${summary.from} — ${summary.to}';
  String get currencyCode => summary.currencyCode;
}

class DashboardRepository {
  DashboardRepository({
    required DashboardApi api,
    LocalPrefs? localPrefs,
  }) : _api = api,
       _localPrefs = localPrefs;

  final DashboardApi _api;
  final LocalPrefs? _localPrefs;

  Future<DashboardHomeData> loadHome(
    String storeId,
    DashboardFilters filters,
  ) async {
    final results = await Future.wait([
      _api.getSalesSummary(storeId, filters),
      _api.getSalesTimeSeries(storeId, filters),
      _api.getSalesPayments(storeId, filters),
    ]);
    return DashboardHomeData(
      summary: results[0] as DashboardSummary,
      timeSeries: results[1] as DashboardTimeSeries,
      payments: results[2] as SalesPaymentsReport,
      loadedAt: DateTime.now(),
    );
  }

  Future<DeviceDashboardPayload> loadKiosk({
    required String deviceId,
    required String deviceToken,
    DashboardFilters filters = const DashboardFilters.today(),
    bool useCacheOnFailure = true,
  }) async {
    try {
      final payload = await _api.getDeviceDashboard(
        deviceId: deviceId,
        deviceToken: deviceToken,
        filters: filters,
      );
      await _cacheKioskPayload(deviceId, payload);
      return payload;
    } catch (e) {
      if (!useCacheOnFailure) rethrow;
      final cached = await readKioskCache(deviceId);
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<DeviceDashboardConfig> fetchDeviceConfig(
    String storeId,
    String deviceId,
  ) async {
    final config = await _api.getDashboardConfig(storeId, deviceId);
    await _localPrefs?.saveCachedDeviceMode(config.deviceMode.apiValue);
    return config;
  }

  Future<DeviceDashboardConfig> activateKioskMode({
    required String storeId,
    required String deviceId,
    required String adminPin,
  }) async {
    final config = await _api.patchDashboardConfig(
      storeId: storeId,
      deviceId: deviceId,
      adminPin: adminPin,
      dashboardEnabled: true,
      deviceMode: DeviceMode.dashboard,
      dashboardView: 'SALES_SUMMARY',
      regenerateToken: true,
    );
    final token = config.dashboardAccessToken;
    if (token != null && token.isNotEmpty) {
      await _localPrefs?.saveDashboardAccessToken(deviceId, token);
    }
    await _localPrefs?.saveCachedDeviceMode(DeviceMode.dashboard.apiValue);
    return config;
  }

  Future<void> _cacheKioskPayload(
    String deviceId,
    DeviceDashboardPayload payload,
  ) async {
    final prefs = _localPrefs;
    if (prefs == null) return;
    final map = {
      'cachedAt': DateTime.now().toIso8601String(),
      'from': payload.from,
      'to': payload.to,
      'timezone': payload.timezone,
      'currencyCode': payload.currencyCode,
      'summary': {
        'grossSales': payload.summary.grossSales,
        'returns': payload.summary.returns,
        'netSales': payload.summary.netSales,
        'tickets': payload.summary.tickets,
        'avgTicket': payload.summary.avgTicket,
        'currencyCode': payload.currencyCode,
      },
      'payments': payload.payments
          .map((p) => {'method': p.method, 'amount': p.amount})
          .toList(),
      'series': payload.series
          .map(
            (p) => {
              'bucket': p.bucket,
              'grossSales': p.grossSales,
              'returns': p.returns,
              'netSales': p.netSales,
              'tickets': p.tickets,
            },
          )
          .toList(),
    };
    await prefs.saveDashboardKioskCache(deviceId, jsonEncode(map));
  }

  Future<DeviceDashboardPayload?> readKioskCache(String deviceId) async {
    final raw = await _localPrefs?.loadDashboardKioskCache(deviceId);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final cachedAt = DateTime.tryParse(decoded['cachedAt']?.toString() ?? '');
      if (cachedAt != null &&
          DateTime.now().difference(cachedAt) > const Duration(minutes: 5)) {
        return null;
      }
      return DeviceDashboardPayload.fromJson({
        'filters': {
          'storeId': '',
          'from': decoded['from'],
          'to': decoded['to'],
          'timezone': decoded['timezone'],
        },
        'summary': decoded['summary'],
        'payments': decoded['payments'],
        'series': decoded['series'],
      });
    } catch (_) {
      return null;
    }
  }
}
