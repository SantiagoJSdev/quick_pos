import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/pos/sale_checkout_payload.dart';
import 'package:quick_pos/core/sync/pending_sale_entry.dart';

void main() {
  test('syncSaleFromRestBody añade storeId y fxSource', () {
    final rest = <String, dynamic>{
      'id': 'sale-uuid-1',
      'documentCurrencyCode': 'VES',
      'deviceId': 'dev-1',
      'lines': [
        {'productId': 'p1', 'quantity': '1', 'price': '10.00', 'discount': '0'},
      ],
      'fxSnapshot': {
        'baseCurrencyCode': 'USD',
        'quoteCurrencyCode': 'VES',
        'rateQuotePerBase': '36.5',
        'effectiveDate': '2026-04-04',
      },
    };
    final sync = SaleCheckoutPayload.syncSaleFromRestBody(
      rest,
      'store-uuid',
      fxSource: 'POS_OFFLINE',
    );
    expect(sync['storeId'], 'store-uuid');
    expect(sync['id'], 'sale-uuid-1');
    expect((sync['fxSnapshot'] as Map)['fxSource'], 'POS_OFFLINE');
  });

  test('coerceSalePayloadForSyncPush convierte números a string (líneas/pagos)', () {
    final raw = <String, dynamic>{
      'storeId': 'store-uuid',
      'documentCurrencyCode': 'VES',
      'deviceId': 'dev',
      'lines': [
        {
          'productId': 'p1',
          'quantity': 2,
          'price': 10.5,
          'discount': 0,
        },
      ],
      'fxSnapshot': {
        'baseCurrencyCode': 'USD',
        'quoteCurrencyCode': 'VES',
        'rateQuotePerBase': 36.5,
        'effectiveDate': '2026-04-04',
      },
      'payments': [
        {
          'method': 'CASH_USD',
          'amount': 5.0,
          'currencyCode': 'USD',
          'fxSnapshot': {
            'baseCurrencyCode': 'USD',
            'quoteCurrencyCode': 'VES',
            'rateQuotePerBase': 36.5,
            'effectiveDate': '2026-04-04',
          },
        },
      ],
    };
    final coerced = SaleCheckoutPayload.coerceSalePayloadForSyncPush(raw);
    final line = (coerced['lines'] as List).first as Map<String, dynamic>;
    expect(line['quantity'], isA<String>());
    expect(line['quantity'], '2');
    expect(line['price'], isA<String>());
    expect(line['price'], '10.5');
    expect(line['discount'], isA<String>());
    final pay = (coerced['payments'] as List).first as Map<String, dynamic>;
    expect(pay['amount'], isA<String>());
    expect(pay['currencyCode'], 'USD');
    final fx = coerced['fxSnapshot'] as Map<String, dynamic>;
    expect(fx['rateQuotePerBase'], isA<String>());
  });

  test('PendingSaleEntry toJson / tryFromJson', () {
    const e = PendingSaleEntry(
      opId: 'op-1',
      storeId: 's1',
      sale: {'id': 'x'},
      opTimestampIso: '2026-04-04T12:00:00.000Z',
    );
    final back = PendingSaleEntry.tryFromJson(e.toJson());
    expect(back?.opId, e.opId);
    expect(back?.sale['id'], 'x');
  });
}
