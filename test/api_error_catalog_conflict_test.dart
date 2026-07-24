import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/api/api_error.dart';

void main() {
  test('traduce unique constraint de barcode a español', () {
    final e = ApiError(
      statusCode: 409,
      error: 'Conflict',
      messages: [
        'Unique constraint failed on the fields: (`storeId`,`barcode`)',
      ],
      requestId: 'abc',
    );
    expect(e.catalogConflictMessageEs, contains('código de barras'));
    expect(e.catalogConflictMessageEs.toLowerCase(), isNot(contains('unique')));
  });

  test('stock insuficiente tiene mensaje claro en POS', () {
    final e = ApiError(
      statusCode: 400,
      error: 'Bad Request',
      messages: ['INSUFFICIENT_STOCK for product'],
    );
    expect(e.looksLikeInsufficientStock, isTrue);
    expect(e.posCheckoutMessageEs, contains('no hay stock'));
  });

  test('traduce duplicate sku a español', () {
    final e = ApiError(
      statusCode: 400,
      error: 'Bad Request',
      messages: ['SKU already exists'],
    );
    expect(e.catalogConflictMessageEs, contains('SKU'));
  });

  test('otros errores conservan mensaje de soporte', () {
    final e = ApiError(
      statusCode: 400,
      error: 'Bad Request',
      messages: ['price must be a number'],
      requestId: 'x1',
    );
    expect(e.catalogConflictMessageEs, contains('price must be a number'));
    expect(e.catalogConflictMessageEs, contains('requestId'));
  });
}
