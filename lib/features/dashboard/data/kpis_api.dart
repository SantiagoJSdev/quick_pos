import '../../../core/api/api_client.dart';
import '../domain/kpi_snapshot.dart';

/// `GET /api/v1/kpis/snapshot` — `docs/KPI_SNAPSHOT_FRONTEND.md`.
class KpisApi {
  KpisApi(this._client);

  final ApiClient _client;

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
}
