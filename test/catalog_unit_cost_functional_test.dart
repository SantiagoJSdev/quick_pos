import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/models/latest_exchange_rate.dart';
import 'package:quick_pos/core/pos/catalog_unit_cost_functional.dart';
import 'package:quick_pos/core/pos/sale_checkout_payload.dart';

void main() {
  test('catalogUnitCostFunctional costo ya en moneda funcional', () {
    final s = catalogUnitCostFunctional(
      catalogCost: '1.25',
      catalogCurrency: 'USD',
      functionalCurrencyCode: 'USD',
      documentCurrencyCode: 'VES',
      pair: null,
    );
    expect(s, '1.250000');
  });

  test('catalogUnitCostFunctional costo en moneda documento → funcional', () {
    final rate = LatestExchangeRate(
      baseCurrencyCode: 'USD',
      quoteCurrencyCode: 'VES',
      rateQuotePerBase: '36.5',
      effectiveDate: '2026-01-01',
    );
    final pair = SaleFxPair(rate: rate, inverted: false);
    final s = catalogUnitCostFunctional(
      catalogCost: '36.5',
      catalogCurrency: 'VES',
      functionalCurrencyCode: 'USD',
      documentCurrencyCode: 'VES',
      pair: pair,
    );
    expect(s, '1.000000');
  });

  test('catalogUnitCostFunctional costo 0', () {
    expect(
      catalogUnitCostFunctional(
        catalogCost: '0',
        catalogCurrency: 'USD',
        functionalCurrencyCode: 'USD',
        documentCurrencyCode: 'VES',
        pair: null,
      ),
      '0.00',
    );
  });

  test('catalogUnitCostFunctional moneda producto no soportada', () {
    expect(
      catalogUnitCostFunctional(
        catalogCost: '10',
        catalogCurrency: 'EUR',
        functionalCurrencyCode: 'USD',
        documentCurrencyCode: 'VES',
        pair: null,
      ),
      isNull,
    );
  });
}
