/// Respuesta de `GET /api/v1/sales` con `format=object` (default).
/// Ver `docs/BACKEND_SALES_HISTORY_API.md`.
class SalesListItem {
  const SalesListItem({
    required this.id,
    this.createdAt,
    this.documentCurrencyCode,
    this.totalDocument,
    this.totalFunctional,
    this.deviceId,
    this.status,
  });

  final String id;
  final String? createdAt;
  final String? documentCurrencyCode;
  final String? totalDocument;
  final String? totalFunctional;
  final String? deviceId;
  final String? status;

  static SalesListItem? tryFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString();
    if (id == null || id.isEmpty) return null;
    return SalesListItem(
      id: id,
      createdAt: json['createdAt']?.toString(),
      documentCurrencyCode: json['documentCurrencyCode']?.toString(),
      totalDocument: json['totalDocument']?.toString(),
      totalFunctional: json['totalFunctional']?.toString(),
      deviceId: json['deviceId']?.toString(),
      status: json['status']?.toString(),
    );
  }
}

class SalesListMeta {
  const SalesListMeta({
    this.timezone,
    this.dateFrom,
    this.dateTo,
    this.rangeInterpretation,
    this.limit,
    this.hasMore,
    this.deviceIdFilter,
  });

  final String? timezone;
  final String? dateFrom;
  final String? dateTo;
  final String? rangeInterpretation;
  final int? limit;
  final bool? hasMore;
  final String? deviceIdFilter;

  static SalesListMeta? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return SalesListMeta(
      timezone: json['timezone']?.toString(),
      dateFrom: json['dateFrom']?.toString(),
      dateTo: json['dateTo']?.toString(),
      rangeInterpretation: json['rangeInterpretation']?.toString(),
      limit: _int(json['limit']),
      hasMore: json['hasMore'] is bool ? json['hasMore'] as bool : null,
      deviceIdFilter: json['deviceIdFilter']?.toString(),
    );
  }

  static int? _int(Object? v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }
}

class SalesListPage {
  const SalesListPage({required this.items, this.nextCursor, this.meta});

  final List<SalesListItem> items;
  final String? nextCursor;
  final SalesListMeta? meta;

  bool get hasMore =>
      (meta?.hasMore == true) || (nextCursor != null && nextCursor!.isNotEmpty);

  factory SalesListPage.fromJson(Map<String, dynamic> json) {
    final items = <SalesListItem>[];
    final raw = json['items'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final it = SalesListItem.tryFromJson(Map<String, dynamic>.from(e));
          if (it != null) items.add(it);
        }
      }
    }
    final nc = json['nextCursor'];
    final metaRaw = json['meta'];
    return SalesListPage(
      items: items,
      nextCursor: nc is String && nc.isNotEmpty ? nc : null,
      meta: metaRaw is Map
          ? SalesListMeta.tryFromJson(Map<String, dynamic>.from(metaRaw))
          : null,
    );
  }
}
