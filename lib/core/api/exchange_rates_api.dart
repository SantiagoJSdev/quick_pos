import '../models/latest_exchange_rate.dart';
import 'api_client.dart';

class ExchangeRatesApi {
  ExchangeRatesApi(this._client);

  final ApiClient _client;

  /// `GET /api/v1/exchange-rates/latest` — query `effectiveOn` opcional (YYYY-MM-DD).
  Future<LatestExchangeRate> getLatest(
    String storeId, {
    required String baseCurrencyCode,
    required String quoteCurrencyCode,
    String? effectiveOn,
  }) async {
    final query = <String, String>{
      'baseCurrencyCode': baseCurrencyCode,
      'quoteCurrencyCode': quoteCurrencyCode,
      if (effectiveOn != null && effectiveOn.isNotEmpty) 'effectiveOn': effectiveOn,
    };
    final json = await _client.getJson(
      '/exchange-rates/latest',
      storeId,
      query: query,
    );
    return LatestExchangeRate.fromJson(json);
  }

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
