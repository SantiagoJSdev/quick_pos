/// Respuesta de `GET /api/v1/exchange-rates/latest`.
class LatestExchangeRate {
  const LatestExchangeRate({
    required this.baseCurrencyCode,
    required this.quoteCurrencyCode,
    required this.rateQuotePerBase,
    required this.effectiveDate,
    this.convention,
    this.source,
    this.notes,
    this.id,
    this.storeId,
    this.createdAt,
  });

  final String? id;
  final String? storeId;
  final String baseCurrencyCode;
  final String quoteCurrencyCode;
  final String rateQuotePerBase;
  final String effectiveDate;
  final String? source;
  final String? notes;
  final String? createdAt;
  final String? convention;

  static LatestExchangeRate fromJson(Map<String, dynamic> json) {
    return LatestExchangeRate(
      id: json['id'] as String?,
      storeId: json['storeId'] as String?,
      baseCurrencyCode: json['baseCurrencyCode'] as String? ?? '',
      quoteCurrencyCode: json['quoteCurrencyCode'] as String? ?? '',
      rateQuotePerBase: json['rateQuotePerBase']?.toString() ?? '',
      effectiveDate: json['effectiveDate']?.toString() ?? '',
      source: json['source'] as String?,
      notes: json['notes'] as String?,
      createdAt: json['createdAt'] as String?,
      convention: json['convention'] as String?,
    );
  }
}
