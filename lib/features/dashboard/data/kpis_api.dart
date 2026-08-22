import '../../../core/api/api_client.dart';
import '../domain/kpi_capital_series.dart';
import '../domain/kpi_snapshot.dart';

/// KPIs — `docs/KPI_CONTRATO_FRONT.md`.
class KpisApi {
  KpisApi(this._client);

  final ApiClient _client;

  /// `GET /kpis/snapshot?preset=` o `dateFrom`/`dateTo`.
  Future<KpiSnapshot> getSnapshot(
    String storeId, {
    String preset = 'today',
    String? dateFrom,
    String? dateTo,
  }) async {
    final query = <String, String>{};
    if (dateFrom != null &&
        dateFrom.isNotEmpty &&
        dateTo != null &&
        dateTo.isNotEmpty) {
      query['dateFrom'] = dateFrom;
      query['dateTo'] = dateTo;
    } else if (preset.isNotEmpty) {
      query['preset'] = preset;
    }
    final json = await _client.getJson(
      '/kpis/snapshot',
      storeId,
      query: query.isEmpty ? null : query,
    );
    return KpiSnapshot.fromJson(json);
  }

  /// `GET /kpis/capital-series?preset=week|month` o rango custom (máx. 62 días).
  Future<KpiCapitalSeries> getCapitalSeries(
    String storeId, {
    String preset = 'week',
    String? dateFrom,
    String? dateTo,
  }) async {
    final query = <String, String>{};
    if (dateFrom != null &&
        dateFrom.isNotEmpty &&
        dateTo != null &&
        dateTo.isNotEmpty) {
      query['dateFrom'] = dateFrom;
      query['dateTo'] = dateTo;
    } else if (preset.isNotEmpty) {
      query['preset'] = preset;
    }
    final json = await _client.getJson(
      '/kpis/capital-series',
      storeId,
      query: query.isEmpty ? null : query,
    );
    return KpiCapitalSeries.fromJson(json);
  }
}
