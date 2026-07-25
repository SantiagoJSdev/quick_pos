import 'dashboard_filters.dart';

/// Calendario operativo de reportes: **America/Caracas (UTC−4)**, sin DST.
///
/// El API interpreta `dateFrom`/`dateTo` en la zona de la tienda. Si la tienda
/// quedó en `UTC` (Render), «Hoy» del servidor no coincide con el día en
/// Venezuela. Esta clase fija el día de negocio VE.
class DashboardLocalDates {
  DashboardLocalDates._();

  /// Offset fijo Caracas respecto a UTC.
  static const Duration caracasOffsetFromUtc = Duration(hours: -4);

  static String formatYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Reloj de pared en Caracas (campos y/m/d/h son la hora local VE).
  static DateTime nowInCaracas([DateTime? utcNow]) {
    final utc = (utcNow ?? DateTime.now()).toUtc();
    return utc.add(caracasOffsetFromUtc);
  }

  /// Solo fecha (sin hora) en calendario Caracas.
  static DateTime todayCaracas([DateTime? utcNow]) {
    final n = nowInCaracas(utcNow);
    return DateTime(n.year, n.month, n.day);
  }

  /// Convierte un instante UTC (o local del device) a fecha calendario Caracas.
  static DateTime calendarDateInCaracas(DateTime instant) {
    final wall = instant.toUtc().add(caracasOffsetFromUtc);
    return DateTime(wall.year, wall.month, wall.day);
  }

  static DateTime? parseYmd(String raw) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
    if (m == null) return null;
    final y = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final d = int.tryParse(m.group(3)!);
    if (y == null || mo == null || d == null) return null;
    return DateTime(y, mo, d);
  }

  static ({String from, String to}) rangeForPreset(
    DashboardPreset preset, {
    DateTime? now,
  }) {
    // [now] si viene de tests es reloj Caracas; si no, convertimos UTC→Caracas.
    final today = now != null
        ? DateTime(now.year, now.month, now.day)
        : todayCaracas();
    switch (preset) {
      case DashboardPreset.today:
        final ymd = formatYmd(today);
        return (from: ymd, to: ymd);
      case DashboardPreset.yesterday:
        final y = today.subtract(const Duration(days: 1));
        final ymd = formatYmd(y);
        return (from: ymd, to: ymd);
      case DashboardPreset.week:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (from: formatYmd(monday), to: formatYmd(today));
      case DashboardPreset.month:
        final first = DateTime(today.year, today.month, 1);
        return (from: formatYmd(first), to: formatYmd(today));
    }
  }

  /// Rango de negocio (Caracas) que el filtro pretende mostrar.
  static ({DateTime from, DateTime to})? businessRange(
    DashboardFilters filters, {
    DateTime? now,
  }) {
    if (filters.preset != null) {
      final r = rangeForPreset(filters.preset!, now: now);
      final from = parseYmd(r.from);
      final to = parseYmd(r.to);
      if (from == null || to == null) return null;
      return (from: from, to: to);
    }
    final from = filters.dateFrom != null ? parseYmd(filters.dateFrom!) : null;
    final to = filters.dateTo != null ? parseYmd(filters.dateTo!) : null;
    if (from == null || to == null) return null;
    return (from: from, to: to);
  }

  /// Amplía ±1 día calendario para pedir al API cuando la tienda está en UTC.
  static ({String from, String to}) utcFetchWindow(DateTime from, DateTime to) {
    final wideFrom = from.subtract(const Duration(days: 1));
    final wideTo = to.add(const Duration(days: 1));
    return (from: formatYmd(wideFrom), to: formatYmd(wideTo));
  }
}
