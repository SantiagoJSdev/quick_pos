import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/models/latest_exchange_rate.dart';
import 'package:quick_pos/core/pos/purchase_unit_cost_convert.dart';
import 'package:quick_pos/core/pos/sale_checkout_payload.dart';

void main() {
  test('purchaseUnitCostInProductCurrency misma moneda que documento', () {
    final s = purchaseUnitCostInProductCurrency(
      unitCostDocument: '10.50',
      documentCurrencyCode: 'VES',
      functionalCurrencyCode: 'USD',
      fxPair: null,
      productCurrencyCode: 'VES',
    );
    expect(s, '10.500000');
  });

  test('purchaseUnitCostInProductCurrency documento → funcional', () {
    final rate = LatestExchangeRate(
      baseCurrencyCode: 'USD',
      quoteCurrencyCode: 'VES',
      rateQuotePerBase: '36.5',
      effectiveDate: '2026-01-01',
    );
    final pair = SaleFxPair(rate: rate, inverted: false);
    final s = purchaseUnitCostInProductCurrency(
      unitCostDocument: '365',
      documentCurrencyCode: 'VES',
      functionalCurrencyCode: 'USD',
      fxPair: pair,
      productCurrencyCode: 'USD',
    );
    expect(s, '10.000000');
  });

  test('purchaseUnitCostInProductCurrency moneda producto no soportada', () {
    expect(
      purchaseUnitCostInProductCurrency(
        unitCostDocument: '10',
        documentCurrencyCode: 'VES',
        functionalCurrencyCode: 'USD',
        fxPair: null,
        productCurrencyCode: 'EUR',
      ),
      isNull,
    );
  });
}
