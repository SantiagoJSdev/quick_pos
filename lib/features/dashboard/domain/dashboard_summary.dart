/// KPIs de `GET /reports/sales/summary` — montos como [String], sin recalcular en cliente.
class DashboardSummary {
  const DashboardSummary({
    required this.storeId,
    required this.currencyCode,
    required this.from,
    required this.to,
    required this.timezone,
    required this.grossSales,
    required this.returns,
    required this.netSales,
    required this.tickets,
    required this.avgTicket,
    this.returnRate,
    this.preset,
    this.rangeInterpretation,
  });

  final String storeId;
  final String currencyCode;
  final String from;
  final String to;
  final String timezone;
  final String grossSales;
  final String returns;
  final String netSales;
  final int tickets;
  final String avgTicket;
  final String? returnRate;
  final String? preset;
  final String? rangeInterpretation;

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    return DashboardSummary(
      storeId: json['storeId']?.toString() ?? '',
      currencyCode: json['currencyCode']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      timezone: json['timezone']?.toString() ?? '',
      grossSales: json['grossSales']?.toString() ?? '0',
      returns: json['returns']?.toString() ?? '0',
      netSales: json['netSales']?.toString() ?? '0',
      tickets: _parseInt(json['tickets']),
      avgTicket: json['avgTicket']?.toString() ?? '0',
      returnRate: json['returnRate']?.toString(),
      preset: json['preset']?.toString(),
      rangeInterpretation: json['rangeInterpretation']?.toString(),
    );
  }

  /// Subconjunto en payload kiosk (`summary` anidado).
  factory DashboardSummary.fromKioskSummary(
    Map<String, dynamic> json, {
    required String storeId,
    required String from,
    required String to,
    required String timezone,
  }) {
    return DashboardSummary(
      storeId: storeId,
      currencyCode: json['currencyCode']?.toString() ?? '',
      from: from,
      to: to,
      timezone: timezone,
      grossSales: json['grossSales']?.toString() ?? '0',
      returns: json['returns']?.toString() ?? '0',
      netSales: json['netSales']?.toString() ?? '0',
      tickets: _parseInt(json['tickets']),
      avgTicket: json['avgTicket']?.toString() ?? '0',
      returnRate: null,
    );
  }

  static int _parseInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}
