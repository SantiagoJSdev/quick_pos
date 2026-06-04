import 'dashboard_summary.dart';
import 'dashboard_timeseries.dart';
import 'payment_breakdown_item.dart';

class DeviceDashboardPayload {
  const DeviceDashboardPayload({
    required this.summary,
    required this.payments,
    required this.series,
    required this.from,
    required this.to,
    required this.timezone,
    required this.currencyCode,
    this.preset,
  });

  final DashboardSummary summary;
  final List<PaymentBreakdownItem> payments;
  final List<TimeSeriesPoint> series;
  final String from;
  final String to;
  final String timezone;
  final String currencyCode;
  final String? preset;

  factory DeviceDashboardPayload.fromJson(Map<String, dynamic> json) {
    final filters = json['filters'];
    final f = filters is Map<String, dynamic>
        ? filters
        : (filters is Map ? Map<String, dynamic>.from(filters) : <String, dynamic>{});
    final storeId = f['storeId']?.toString() ?? '';
    final from = f['from']?.toString() ?? '';
    final to = f['to']?.toString() ?? '';
    final timezone = f['timezone']?.toString() ?? '';
    final preset = f['preset']?.toString();

    final summaryRaw = json['summary'];
    final summaryMap = summaryRaw is Map<String, dynamic>
        ? summaryRaw
        : (summaryRaw is Map
              ? Map<String, dynamic>.from(summaryRaw)
              : <String, dynamic>{});

    final paymentsRaw = json['payments'];
    final payments = <PaymentBreakdownItem>[];
    if (paymentsRaw is List) {
      for (final e in paymentsRaw) {
        if (e is Map<String, dynamic>) {
          payments.add(PaymentBreakdownItem.fromJson(e));
        } else if (e is Map) {
          payments.add(
            PaymentBreakdownItem.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }

    final seriesRaw = json['series'];
    final series = <TimeSeriesPoint>[];
    if (seriesRaw is List) {
      for (final e in seriesRaw) {
        if (e is Map<String, dynamic>) {
          series.add(TimeSeriesPoint.fromJson(e));
        } else if (e is Map) {
          series.add(TimeSeriesPoint.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }

    final currencyCode = summaryMap['currencyCode']?.toString() ?? 'USD';

    return DeviceDashboardPayload(
      summary: DashboardSummary.fromKioskSummary(
        summaryMap,
        storeId: storeId,
        from: from,
        to: to,
        timezone: timezone,
      ),
      payments: payments,
      series: series,
      from: from,
      to: to,
      timezone: timezone,
      currencyCode: currencyCode,
      preset: preset,
    );
  }
}
