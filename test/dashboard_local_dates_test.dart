import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/features/dashboard/domain/dashboard_filters.dart';
import 'package:quick_pos/features/dashboard/domain/dashboard_local_dates.dart';

void main() {
  test('Hoy usa calendario Caracas, no UTC (caso noche Venezuela)', () {
    // 23 jul 2026 21:00 VE (ya pasado como reloj Caracas en el test).
    final caracasEvening = DateTime(2026, 7, 23, 21, 0);
    final q = const DashboardFilters.today().toQueryParams(now: caracasEvening);
    expect(q['preset'], isNull);
    expect(q['dateFrom'], '2026-07-23');
    expect(q['dateTo'], '2026-07-23');
  });

  test('Instante UTC de madrugada sigue siendo el día VE anterior', () {
    // 24 jul 2026 01:00 UTC = 23 jul 2026 21:00 Caracas.
    final utc = DateTime.utc(2026, 7, 24, 1, 0);
    final day = DashboardLocalDates.calendarDateInCaracas(utc);
    expect(DashboardLocalDates.formatYmd(day), '2026-07-23');
  });

  test('Ayer / semana / mes se resuelven en Caracas', () {
    final now = DateTime(2026, 7, 24, 10, 0); // viernes
    expect(
      DashboardLocalDates.rangeForPreset(DashboardPreset.yesterday, now: now),
      (from: '2026-07-23', to: '2026-07-23'),
    );
    expect(
      DashboardLocalDates.rangeForPreset(DashboardPreset.week, now: now),
      (from: '2026-07-20', to: '2026-07-24'),
    );
    expect(
      DashboardLocalDates.rangeForPreset(DashboardPreset.month, now: now),
      (from: '2026-07-01', to: '2026-07-24'),
    );
  });

  test('Ventana UTC de fetch amplía ±1 día', () {
    final from = DateTime(2026, 7, 24);
    final to = DateTime(2026, 7, 24);
    expect(
      DashboardLocalDates.utcFetchWindow(from, to),
      (from: '2026-07-23', to: '2026-07-25'),
    );
  });
}
