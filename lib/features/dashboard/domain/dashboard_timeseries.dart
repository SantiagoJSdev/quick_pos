class TimeSeriesMeta {
  const TimeSeriesMeta({
    required this.timezone,
    required this.from,
    required this.to,
    required this.groupBy,
    this.preset,
    this.rangeInterpretation,
  });

  final String timezone;
  final String from;
  final String to;
  final String groupBy;
  final String? preset;
  final String? rangeInterpretation;

  factory TimeSeriesMeta.fromJson(Map<String, dynamic> json) {
    return TimeSeriesMeta(
      timezone: json['timezone']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      groupBy: json['groupBy']?.toString() ?? 'day',
      preset: json['preset']?.toString(),
      rangeInterpretation: json['rangeInterpretation']?.toString(),
    );
  }
}

class TimeSeriesPoint {
  const TimeSeriesPoint({
    required this.bucket,
    required this.grossSales,
    required this.returns,
    required this.netSales,
    required this.tickets,
  });

  final String bucket;
  final String grossSales;
  final String returns;
  final String netSales;
  final int tickets;

  factory TimeSeriesPoint.fromJson(Map<String, dynamic> json) {
    return TimeSeriesPoint(
      bucket: json['bucket']?.toString() ?? '',
      grossSales: json['grossSales']?.toString() ?? '0',
      returns: json['returns']?.toString() ?? '0',
      netSales: json['netSales']?.toString() ?? '0',
      tickets: _parseInt(json['tickets']),
    );
  }

  static int _parseInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

class DashboardTimeSeries {
  const DashboardTimeSeries({
    required this.meta,
    required this.points,
  });

  final TimeSeriesMeta meta;
  final List<TimeSeriesPoint> points;

  factory DashboardTimeSeries.fromJson(Map<String, dynamic> json) {
    final metaRaw = json['meta'];
    final meta = metaRaw is Map<String, dynamic>
        ? TimeSeriesMeta.fromJson(metaRaw)
        : const TimeSeriesMeta(
            timezone: '',
            from: '',
            to: '',
            groupBy: 'day',
          );
    final pts = json['points'];
    final list = <TimeSeriesPoint>[];
    if (pts is List) {
      for (final e in pts) {
        if (e is Map<String, dynamic>) {
          list.add(TimeSeriesPoint.fromJson(e));
        } else if (e is Map) {
          list.add(TimeSeriesPoint.fromJson(Map<String, dynamic>.from(e)));
        }
      }
    }
    return DashboardTimeSeries(meta: meta, points: list);
  }
}
