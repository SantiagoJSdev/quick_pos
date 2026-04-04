import 'api_client.dart';

class ExchangeRatesApi {
  ExchangeRatesApi(this._client);

  final ApiClient _client;

  /// `POST /api/v1/exchange-rates` — `FRONTEND_INTEGRATION_CONTEXT.md` (tasas).
  Future<Map<String, dynamic>> createRate(
    String storeId, {
    required String baseCurrencyCode,
    required String quoteCurrencyCode,
    required String rateQuotePerBase,
    required String effectiveDate,
    String? source,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'baseCurrencyCode': baseCurrencyCode,
      'quoteCurrencyCode': quoteCurrencyCode,
      'rateQuotePerBase': rateQuotePerBase,
      'effectiveDate': effectiveDate,
    };
    if (source != null) body['source'] = source;
    if (notes != null) body['notes'] = notes;
    return _client.postJson('/exchange-rates', storeId, body);
  }
}
