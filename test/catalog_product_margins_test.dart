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

  test('toPatchBody USE_STORE_DEFAULT sin clave marginPercentOverride', () {
    final m = _base().toPatchBody();
    expect(m['pricingMode'], 'USE_STORE_DEFAULT');
    expect(m.containsKey('marginPercentOverride'), false);
  });

  test('toPatchBody USE_PRODUCT_OVERRIDE', () {
    final m = _base(
      pricingMode: 'USE_PRODUCT_OVERRIDE',
      marginPercentOverride: '18.5',
    ).toPatchBody();
    expect(m['pricingMode'], 'USE_PRODUCT_OVERRIDE');
    expect(m['marginPercentOverride'], '18.5');
  });

  test('toPatchBody no envía null en JSON (barcode vacío → string vacío)', () {
    final m = _base().toPatchBody();
    expect(m['barcode'], '');
    expect(m.containsKey('supplierId'), false);
    expect(m.values.where((v) => v == null), isEmpty);
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

  test('fromJson supplier anidado supplier.id', () {
    final p = CatalogProduct.fromJson({
      'id': 'p1',
      'sku': 's',
      'name': 'n',
      'price': '1',
      'cost': '1',
      'currency': 'USD',
      'active': true,
      'supplier': {'id': '11111111-1111-4111-8111-111111111111', 'name': 'ACME'},
    });
    expect(p.supplierId, '11111111-1111-4111-8111-111111111111');
  });

  test('withResolvedSupplierId rellena si la respuesta omitió supplierId', () {
    final received = CatalogProduct(
      id: 'p1',
      sku: 'SKU',
      name: 'N',
      price: '10',
      cost: '5',
      currency: 'USD',
      active: true,
      supplierId: null,
    );
    final merged = received.withResolvedSupplierId(
      '22222222-2222-4222-8222-222222222222',
    );
    expect(merged.supplierId, '22222222-2222-4222-8222-222222222222');
  });

  test('withResolvedSupplierId no pisa supplierId ya presente', () {
    final received = CatalogProduct(
      id: 'p1',
      sku: 'SKU',
      name: 'N',
      price: '10',
      cost: '5',
      currency: 'USD',
      active: true,
      supplierId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    );
    final merged = received.withResolvedSupplierId(
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    );
    expect(merged.supplierId, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
  });
}
