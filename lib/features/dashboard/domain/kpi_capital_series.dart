/// Respuesta de `GET /api/v1/kpis/capital-series` — `docs/KPI_CONTRATO_FRONT.md` §4.
class KpiCapitalSeries {
  const KpiCapitalSeries({
    this.from,
    this.to,
    this.missingDates = const [],
    this.lazyYesterday = false,
    this.items = const [],
  });

  final String? from;
  final String? to;
  final List<String> missingDates;
  final bool lazyYesterday;
  final List<KpiCapitalSeriesItem> items;

  static KpiCapitalSeries fromJson(Map<String, dynamic> json) {
    final missing = <String>[];
    final rawMissing = json['missingDates'];
    if (rawMissing is List) {
      for (final e in rawMissing) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty) missing.add(s);
      }
    }
    final items = <KpiCapitalSeriesItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          final item =
              KpiCapitalSeriesItem.tryFromJson(Map<String, dynamic>.from(e));
          if (item != null) items.add(item);
        }
      }
    }
    return KpiCapitalSeries(
      from: json['from']?.toString(),
      to: json['to']?.toString(),
      missingDates: missing,
      lazyYesterday: json['lazyYesterday'] == true,
      items: items,
    );
  }
}

class KpiCapitalSeriesItem {
  const KpiCapitalSeriesItem({
    required this.date,
    this.inventoryCapital,
    this.payablesDue,
    this.netInventoryEquity,
    this.realProfit,
    this.lossCostFunctional,
    this.purchasesFunctional,
    this.supplierPayments,
    this.deltaEquity,
    this.source,
    this.capturedAt,
  });

  final String date;
  final String? inventoryCapital;
  final String? payablesDue;
  final String? netInventoryEquity;
  final String? realProfit;
  final String? lossCostFunctional;
  final String? purchasesFunctional;
  final String? supplierPayments;

  /// `null` si no hay foto del día anterior — no inventar flecha.
  final String? deltaEquity;
  final String? source;
  final String? capturedAt;

  static KpiCapitalSeriesItem? tryFromJson(Map<String, dynamic> json) {
    final date = json['date']?.toString().trim() ?? '';
    if (date.isEmpty) return null;
    final deltaRaw = json['deltaEquity'];
    return KpiCapitalSeriesItem(
      date: date,
      inventoryCapital: json['inventoryCapital']?.toString(),
      payablesDue: json['payablesDue']?.toString(),
      netInventoryEquity: json['netInventoryEquity']?.toString(),
      realProfit: json['realProfit']?.toString(),
      lossCostFunctional: json['lossCostFunctional']?.toString(),
      purchasesFunctional: json['purchasesFunctional']?.toString(),
      supplierPayments: json['supplierPayments']?.toString(),
      deltaEquity: deltaRaw == null ? null : deltaRaw.toString(),
      source: json['source']?.toString(),
      capturedAt: json['capturedAt']?.toString(),
    );
  }
}
