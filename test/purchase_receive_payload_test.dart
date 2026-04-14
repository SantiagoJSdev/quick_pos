import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/sync/purchase_receive_payload.dart';

void main() {
  test('buildSupplierInvoiceReferenceForApi solo factura', () {
    expect(
      PurchaseReceivePayload.buildSupplierInvoiceReferenceForApi(
        invoiceRef: ' FAC-1 ',
        documentNotes: '',
      ),
      'FAC-1',
    );
  });

  test('buildSupplierInvoiceReferenceForApi solo notas', () {
    expect(
      PurchaseReceivePayload.buildSupplierInvoiceReferenceForApi(
        invoiceRef: '',
        documentNotes: ' Entrega ',
      ),
      'Entrega',
    );
  });

  test('buildSupplierInvoiceReferenceForApi factura y notas', () {
    expect(
      PurchaseReceivePayload.buildSupplierInvoiceReferenceForApi(
        invoiceRef: 'A',
        documentNotes: 'B',
      ),
      'A · B',
    );
  });

  test('toRestBody usa supplierInvoiceReference; no reference ni notes', () {
    final body = PurchaseReceivePayload.toRestBody(
      supplierId: '11111111-1111-4111-8111-111111111111',
      documentCurrencyCode: 'VES',
      lines: [
        PurchaseReceivePayload.line(
          productId: '22222222-2222-4222-8222-222222222222',
          quantity: '1',
          unitCost: '10',
        ),
      ],
      fxSnapshot: const {
        'baseCurrencyCode': 'USD',
        'quoteCurrencyCode': 'VES',
        'rateQuotePerBase': '36.50',
        'effectiveDate': '2026-04-13',
      },
      supplierInvoiceReference: 'FAC-2026-0042',
    );
    expect(body.containsKey('reference'), isFalse);
    expect(body.containsKey('notes'), isFalse);
    expect(body['supplierInvoiceReference'], 'FAC-2026-0042');
  });

  test('toSyncPurchaseObject incluye supplierInvoiceReference', () {
    final o = PurchaseReceivePayload.toSyncPurchaseObject(
      storeId: '11111111-1111-4111-8111-111111111111',
      supplierId: '22222222-2222-4222-8222-222222222222',
      documentCurrencyCode: 'VES',
      lines: [
        PurchaseReceivePayload.line(
          productId: '33333333-3333-4333-8333-333333333333',
          quantity: '1',
          unitCost: '2',
        ),
      ],
      fxSnapshot: const {
        'baseCurrencyCode': 'USD',
        'quoteCurrencyCode': 'VES',
        'rateQuotePerBase': '36.50',
        'effectiveDate': '2026-04-13',
      },
      fxSource: 'POS_OFFLINE',
      supplierInvoiceReference: 'FAC-SYNC-001',
    );
    expect(o.containsKey('reference'), isFalse);
    expect(o['supplierInvoiceReference'], 'FAC-SYNC-001');
    final fx = o['fxSnapshot'] as Map<String, dynamic>;
    expect(fx['fxSource'], 'POS_OFFLINE');
  });
}
