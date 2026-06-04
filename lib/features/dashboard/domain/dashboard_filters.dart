/// Filtros de reportes — solo query params; el backend calcula fechas con `preset`.
class DashboardFilters {
  const DashboardFilters({
    this.preset,
    this.dateFrom,
    this.dateTo,
    this.deviceId,
  }) : assert(
         preset != null ||
             (dateFrom != null && dateTo != null) ||
             (preset == null && dateFrom == null && dateTo == null),
         'Usar preset o rango custom',
       );

  /// Sin preset ni fechas → backend usa últimos 7 días.
  const DashboardFilters.lastSevenDays() : this();

  const DashboardFilters.today() : this(preset: DashboardPreset.today);

  final DashboardPreset? preset;
  final String? dateFrom;
  final String? dateTo;
  final String? deviceId;

  Map<String, String> toQueryParams() {
    final q = <String, String>{};
    if (preset != null) {
      q['preset'] = preset!.apiValue;
      return q;
    }
    if (dateFrom != null && dateFrom!.isNotEmpty) {
      q['dateFrom'] = dateFrom!;
    }
    if (dateTo != null && dateTo!.isNotEmpty) {
      q['dateTo'] = dateTo!;
    }
    if (deviceId != null && deviceId!.isNotEmpty) {
      q['deviceId'] = deviceId!;
    }
    return q;
  }

  DashboardFilters copyWith({
    DashboardPreset? preset,
    String? dateFrom,
    String? dateTo,
    String? deviceId,
    bool clearPreset = false,
    bool clearDates = false,
  }) {
    return DashboardFilters(
      preset: clearPreset ? null : (preset ?? this.preset),
      dateFrom: clearDates ? null : (dateFrom ?? this.dateFrom),
      dateTo: clearDates ? null : (dateTo ?? this.dateTo),
      deviceId: deviceId ?? this.deviceId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DashboardFilters &&
        other.preset == preset &&
        other.dateFrom == dateFrom &&
        other.dateTo == dateTo &&
        other.deviceId == deviceId;
  }

  @override
  int get hashCode => Object.hash(preset, dateFrom, dateTo, deviceId);
}

enum DashboardPreset {
  today('today', 'Hoy'),
  yesterday('yesterday', 'Ayer'),
  week('week', 'Esta semana'),
  month('month', 'Este mes');

  const DashboardPreset(this.apiValue, this.label);

  final String apiValue;
  final String label;
}
