import 'dart:convert';

import '../../../core/api/sales_api.dart';
import '../../../core/models/sales_list_page.dart';
import '../../../core/storage/local_prefs.dart';
import '../domain/dashboard_filters.dart';
import '../domain/dashboard_local_dates.dart';
import '../domain/dashboard_summary.dart';
import '../domain/dashboard_timeseries.dart';
import '../domain/dashboard_device_access.dart';
import '../domain/device_dashboard_config.dart';
import '../domain/device_dashboard_payload.dart';
import '../domain/payment_breakdown_item.dart';
import 'dashboard_api.dart';
import 'kpis_api.dart';
import '../domain/kpi_snapshot.dart';

/// Estado agregado del tablero operador (3 endpoints en paralelo).
class DashboardHomeData {
  const DashboardHomeData({
    required this.summary,
    required this.timeSeries,
    required this.payments,
    required this.loadedAt,
    this.totalsCorrectedForCaracas = false,
  });

  final DashboardSummary summary;
  final DashboardTimeSeries timeSeries;
  final SalesPaymentsReport payments;
  final DateTime loadedAt;

  /// KPIs recalculados con calendario America/Caracas porque la tienda está en UTC.
  final bool totalsCorrectedForCaracas;

  String get periodLabel {
    final tz = summary.timezone.trim();
    final range = '${summary.from} — ${summary.to}';
    if (tz.isEmpty) return range;
    return '$range · $tz';
  }

  String get currencyCode => summary.currencyCode;
}

class DashboardRepository {
  DashboardRepository({
    required DashboardApi api,
    KpisApi? kpisApi,
    SalesApi? salesApi,
    LocalPrefs? localPrefs,
  }) : _api = api,
       _kpisApi = kpisApi,
       _salesApi = salesApi,
       _localPrefs = localPrefs;

  final DashboardApi _api;
  final KpisApi? _kpisApi;
  final SalesApi? _salesApi;
  final LocalPrefs? _localPrefs;

  /// `GET /kpis/snapshot` — requiere [KpisApi] en el constructor.
  Future<KpiSnapshot> loadKpiSnapshot(
    String storeId, {
    String preset = 'today',
    String? dateFrom,
    String? dateTo,
  }) {
    final api = _kpisApi;
    if (api == null) {
      throw StateError('KpisApi no configurado en DashboardRepository');
    }
    return api.getSnapshot(
      storeId,
      preset: preset,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );
  }

  Future<DashboardHomeData> loadHome(
    String storeId,
    DashboardFilters filters,
  ) async {
    final results = await Future.wait([
      _api.getSalesSummary(storeId, filters),
      _api.getSalesTimeSeries(storeId, filters),
      _api.getSalesPayments(storeId, filters),
    ]);
    var summary = results[0] as DashboardSummary;
    var corrected = false;
    if (_shouldCorrectUtcStoreToCaracas(summary)) {
      final fixed = await _recomputeSummaryInCaracas(storeId, filters, summary);
      if (fixed != null) {
        summary = fixed;
        corrected = true;
      }
    }
    return DashboardHomeData(
      summary: summary,
      timeSeries: results[1] as DashboardTimeSeries,
      payments: results[2] as SalesPaymentsReport,
      loadedAt: DateTime.now(),
      totalsCorrectedForCaracas: corrected,
    );
  }

  bool _shouldCorrectUtcStoreToCaracas(DashboardSummary summary) {
    final tz = summary.timezone.trim().toUpperCase();
    return tz == 'UTC' || tz == 'ETC/UTC' || tz == 'GMT';
  }

  /// Si la tienda reporta en UTC, los `dateFrom`/`dateTo` no coinciden con el
  /// día comercial en Venezuela. Recalculamos KPIs desde `GET /sales` filtrando
  /// por calendario America/Caracas.
  Future<DashboardSummary?> _recomputeSummaryInCaracas(
    String storeId,
    DashboardFilters filters,
    DashboardSummary server,
  ) async {
    final salesApi = _salesApi;
    if (salesApi == null) return null;
    final range = DashboardLocalDates.businessRange(filters);
    if (range == null) return null;

    final window = DashboardLocalDates.utcFetchWindow(range.from, range.to);
    final items = await _loadAllSalesInWindow(
      salesApi,
      storeId,
      dateFrom: window.from,
      dateTo: window.to,
    );

    final inRange = <SalesListItem>[];
    for (final it in items) {
      if (!_isCountableSale(it)) continue;
      final created = DateTime.tryParse(it.createdAt ?? '');
      if (created == null) continue;
      final day = DashboardLocalDates.calendarDateInCaracas(created);
      if (day.isBefore(range.from) || day.isAfter(range.to)) continue;
      inRange.add(it);
    }

    var gross = 0.0;
    for (final it in inRange) {
      gross += _parseMoney(it.totalFunctional);
    }
    final tickets = inRange.length;
    final avg = tickets == 0 ? 0.0 : gross / tickets;
    final from = DashboardLocalDates.formatYmd(range.from);
    final to = DashboardLocalDates.formatYmd(range.to);

    return DashboardSummary(
      storeId: server.storeId.isNotEmpty ? server.storeId : storeId,
      currencyCode: server.currencyCode.isNotEmpty
          ? server.currencyCode
          : 'USD',
      from: from,
      to: to,
      timezone: 'America/Caracas',
      grossSales: _moneyString(gross),
      returns: '0',
      netSales: _moneyString(gross),
      tickets: tickets,
      avgTicket: _moneyString(avg),
      returnRate: null,
      preset: server.preset,
      rangeInterpretation:
          'Totales recalculados en el dispositivo con calendario '
          'America/Caracas (UTC−4). La tienda en el servidor sigue en UTC; '
          'conviene cambiar timezone de la tienda a America/Caracas.',
    );
  }

  Future<List<SalesListItem>> _loadAllSalesInWindow(
    SalesApi salesApi,
    String storeId, {
    required String dateFrom,
    required String dateTo,
  }) async {
    final all = <SalesListItem>[];
    String? cursor;
    for (var page = 0; page < 20; page++) {
      final batch = await salesApi.listSales(
        storeId,
        dateFrom: dateFrom,
        dateTo: dateTo,
        limit: 200,
        cursor: cursor,
      );
      all.addAll(batch.items);
      if (!batch.hasMore) break;
      cursor = batch.nextCursor;
      if (cursor == null || cursor.isEmpty) break;
    }
    return all;
  }

  static bool _isCountableSale(SalesListItem it) {
    final s = (it.status ?? '').trim().toUpperCase();
    if (s.isEmpty) return true;
    if (s.contains('CANCEL') || s.contains('VOID') || s == 'DRAFT') {
      return false;
    }
    return true;
  }

  static double _parseMoney(String? raw) {
    if (raw == null) return 0;
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? 0;
  }

  static String _moneyString(double v) => v.toStringAsFixed(2);

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
    await _cacheDeviceConfig(deviceId, config);
    return config;
  }

  /// Si el servidor no responde, usa último `dashboardEnabled` cacheado.
  Future<bool> operationalDashboardVisibleCached(
    String storeId,
    String deviceId, {
    required bool online,
  }) async {
    if (online) {
      try {
        final c = await fetchDeviceConfig(storeId, deviceId);
        return DashboardDeviceAccess.showsOperationalDashboard(c);
      } catch (_) {
        return _readCachedOperationalVisible(deviceId);
      }
    }
    return _readCachedOperationalVisible(deviceId);
  }

  Future<bool> _readCachedOperationalVisible(String deviceId) async {
    final enabled = await _localPrefs?.getCachedDashboardEnabled(deviceId);
    return enabled == true;
  }

  Future<void> _cacheDeviceConfig(
    String deviceId,
    DeviceDashboardConfig config,
  ) async {
    await _localPrefs?.saveCachedDeviceMode(config.deviceMode.apiValue);
    await _localPrefs?.saveCachedDashboardEnabled(
      deviceId,
      config.dashboardEnabled,
    );
  }

  /// Habilita dashboard en este terminal (`PATCH .../dashboard-config`).
  Future<DeviceDashboardConfig> enableOperationalDashboard({
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
      regenerateToken: true,
    );
    final token = config.dashboardAccessToken;
    if (token != null && token.isNotEmpty) {
      await _localPrefs?.saveDashboardAccessToken(deviceId, token);
    }
    await _cacheDeviceConfig(deviceId, config);
    return config;
  }

  /// Oculta dashboard en este terminal (vuelve a POS puro).
  Future<DeviceDashboardConfig> disableOperationalDashboard({
    required String storeId,
    required String deviceId,
    required String adminPin,
  }) async {
    final config = await _api.patchDashboardConfig(
      storeId: storeId,
      deviceId: deviceId,
      adminPin: adminPin,
      dashboardEnabled: false,
      deviceMode: DeviceMode.pos,
    );
    await _localPrefs?.clearDashboardAccessToken(deviceId);
    await _cacheDeviceConfig(deviceId, config);
    return config;
  }

  Future<DeviceDashboardConfig> activateKioskMode({
    required String storeId,
    required String deviceId,
    required String adminPin,
  }) {
    return enableOperationalDashboard(
      storeId: storeId,
      deviceId: deviceId,
      adminPin: adminPin,
    );
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
