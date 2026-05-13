import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/pos/money_string_math.dart';

void main() {
  test('multiply USD x tasa VES (2 x 508 = 1016.00)', () {
    expect(
      MoneyStringMath.multiply('2', '508', fractionDigits: 2),
      '1016.00',
    );
  });

  test('divide kg desde monto funcional (2 / 5.5)', () {
    final kg = MoneyStringMath.divide('2', '5.5', fractionDigits: 10);
    expect(kg.startsWith('0.363636'), true);
    final back = MoneyStringMath.multiply(kg, '5.5', fractionDigits: 2);
    expect(back, '2.00');
  });
}
