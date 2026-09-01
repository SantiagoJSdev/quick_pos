import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/models/pos_cart_line.dart';
import 'package:quick_pos/core/pos/sale_checkout_payload.dart';

PosCartLine _line({required String productId}) {
  return PosCartLine(
    productId: productId,
    name: 'Prod',
    sku: 'SKU',
    catalogUnitPrice: '10',
    catalogCurrency: 'USD',
    documentUnitPrice: '10',
    documentCurrencyCode: 'USD',
    quantity: '1',
  );
}

void main() {
  test('SaleCheckoutPayload.build incluye unitCostFunctional por línea', () {
    final body = SaleCheckoutPayload.build(
      documentCurrencyCode: 'USD',
      functionalCurrencyCode: 'USD',
      lines: [_line(productId: 'p1'), _line(productId: 'p2')],
      fxPair: null,
      deviceId: 'dev',
      appVersion: '1',
      unitCostFunctionalByProductId: {
        'p1': '1.25',
        'p2': '0.00',
      },
      clientSoldAt: '2026-09-01T18:30:00.000Z',
    );
    expect(body['clientSoldAt'], '2026-09-01T18:30:00.000Z');
    final lines = body['lines'] as List;
    expect((lines[0] as Map)['unitCostFunctional'], '1.25');
    expect((lines[1] as Map)['unitCostFunctional'], '0.00');
  });

  test('syncSaleFromRestBody propaga unitCostFunctional y clientSoldAt', () {
    final rest = SaleCheckoutPayload.build(
      documentCurrencyCode: 'USD',
      functionalCurrencyCode: 'USD',
      lines: [_line(productId: 'p1')],
      fxPair: null,
      deviceId: 'dev',
      appVersion: '1',
      unitCostFunctionalByProductId: {'p1': '2.50'},
      clientSoldAt: '2026-09-01T12:00:00.000Z',
    );
    final sync = SaleCheckoutPayload.syncSaleFromRestBody(
      rest,
      'store-1',
      fxSource: 'POS_OFFLINE',
    );
    expect(sync['clientSoldAt'], '2026-09-01T12:00:00.000Z');
    final line = (sync['lines'] as List).first as Map<String, dynamic>;
    expect(line['unitCostFunctional'], '2.50');
  });
}
