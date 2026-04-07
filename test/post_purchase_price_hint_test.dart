import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/models/catalog_product.dart';
import 'package:quick_pos/core/pos/post_purchase_price_hint.dart';

CatalogProduct _p({
  String? pricingMode,
  String? marginPercentOverride,
}) {
  return CatalogProduct(
    id: '1',
    sku: 'S',
    name: 'N',
    price: '10',
    cost: '8',
    currency: 'USD',
    active: true,
    pricingMode: pricingMode,
    marginPercentOverride: marginPercentOverride,
  );
}

void main() {
  test('suggestedListFromAverageCostAndStoreMargin 10 + 15%', () {
    final s = PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
      '10.00',
      '15',
    );
    expect(s, '11.50');
  });

  test('null si falta costo o margen', () {
    expect(
      PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
        null,
        '10',
      ),
      null,
    );
    expect(
      PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
        '5',
        '',
      ),
      null,
    );
  });

  test('marginPercentForAverageCostSuggestion override vs tienda vs manual', () {
    expect(
      PostPurchasePriceHint.marginPercentForAverageCostSuggestion(
        product: _p(
          pricingMode: 'USE_PRODUCT_OVERRIDE',
          marginPercentOverride: '40',
        ),
        storeDefaultMarginPercent: '10',
      ),
      '40',
    );
    expect(
      PostPurchasePriceHint.marginPercentForAverageCostSuggestion(
        product: _p(pricingMode: 'USE_STORE_DEFAULT'),
        storeDefaultMarginPercent: '12',
      ),
      '12',
    );
    expect(
      PostPurchasePriceHint.marginPercentForAverageCostSuggestion(
        product: _p(pricingMode: 'MANUAL_PRICE'),
        storeDefaultMarginPercent: '12',
      ),
      null,
    );
    expect(
      PostPurchasePriceHint.marginPercentForAverageCostSuggestion(
        product: null,
        storeDefaultMarginPercent: '5',
      ),
      '5',
    );
  });
}
