import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/features/sale/pos_cart_quantity.dart';

void main() {
  test('normalizeWeightKg conserva decimales del sheet', () {
    expect(PosCartQuantity.normalizeWeightKg('0.363636'), '0.363636');
  });

  test('normalize recorta vía double (legacy)', () {
    expect(PosCartQuantity.normalize('0.363636'), '0.363636');
  });
}
