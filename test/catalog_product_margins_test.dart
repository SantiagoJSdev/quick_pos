import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/models/catalog_product.dart';

CatalogProduct _base({
  String? pricingMode,
  String? marginPercentOverride,
}) {
  return CatalogProduct(
    id: 'p1',
    sku: 'SKU-1',
    name: 'Producto',
    price: '10.00',
    cost: '8.00',
    currency: 'USD',
    active: true,
    pricingMode: pricingMode,
    marginPercentOverride: marginPercentOverride,
  );
}

void main() {
  test('toCreateBody omite pricingMode en margen de tienda (null)', () {
    final m = _base().toCreateBody();
    expect(m.containsKey('pricingMode'), false);
    expect(m.containsKey('marginPercentOverride'), false);
  });

  test('toCreateBody MANUAL_PRICE', () {
    final m = _base(pricingMode: 'MANUAL_PRICE').toCreateBody();
    expect(m['pricingMode'], 'MANUAL_PRICE');
    expect(m.containsKey('marginPercentOverride'), false);
  });

  test('toCreateBody USE_PRODUCT_OVERRIDE + marginPercentOverride', () {
    final m = _base(
      pricingMode: 'USE_PRODUCT_OVERRIDE',
      marginPercentOverride: '25',
    ).toCreateBody();
    expect(m['pricingMode'], 'USE_PRODUCT_OVERRIDE');
    expect(m['marginPercentOverride'], '25');
  });

  test('toPatchBody USE_STORE_DEFAULT y anula override', () {
    final m = _base().toPatchBody();
    expect(m['pricingMode'], 'USE_STORE_DEFAULT');
    expect(m['marginPercentOverride'], null);
  });

  test('toPatchBody USE_PRODUCT_OVERRIDE', () {
    final m = _base(
      pricingMode: 'USE_PRODUCT_OVERRIDE',
      marginPercentOverride: '18.5',
    ).toPatchBody();
    expect(m['pricingMode'], 'USE_PRODUCT_OVERRIDE');
    expect(m['marginPercentOverride'], '18.5');
  });

  test('fromJson lee campos M7', () {
    final p = CatalogProduct.fromJson({
      'id': 'x',
      'sku': 's',
      'name': 'n',
      'price': '2',
      'cost': '1',
      'currency': 'USD',
      'active': true,
      'pricingMode': 'USE_PRODUCT_OVERRIDE',
      'marginPercentOverride': '30',
      'effectiveMarginPercent': '30',
      'suggestedPrice': '1.30',
    });
    expect(p.pricingMode, 'USE_PRODUCT_OVERRIDE');
    expect(p.marginPercentOverride, '30');
    expect(p.effectiveMarginPercent, '30');
    expect(p.suggestedPrice, '1.30');
  });
}
