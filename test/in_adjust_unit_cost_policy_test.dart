import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/inventory/in_adjust_unit_cost_policy.dart';

void main() {
  group('InAdjustUnitCostPolicy', () {
    test('stock > 0 no exige costo', () {
      const p = InAdjustUnitCostPolicy(
        currentStockQuantity: 5,
        catalogUnitCost: '0',
      );
      expect(p.unitCostRequired, isFalse);
      expect(
        p.validateForSubmit(adjustType: 'IN_ADJUST', unitCostRaw: ''),
        isNull,
      );
    });

    test('stock 0 con catálogo > 0 no exige costo', () {
      const p = InAdjustUnitCostPolicy(
        currentStockQuantity: 0,
        catalogUnitCost: '8.50',
      );
      expect(p.unitCostRequired, isFalse);
      expect(
        p.validateForSubmit(adjustType: 'IN_ADJUST', unitCostRaw: ''),
        isNull,
      );
    });

    test('stock 0 sin catálogo exige costo', () {
      const p = InAdjustUnitCostPolicy(
        currentStockQuantity: 0,
        catalogUnitCost: '0',
      );
      expect(p.unitCostRequired, isTrue);
      expect(
        p.validateForSubmit(adjustType: 'IN_ADJUST', unitCostRaw: ''),
        isNotNull,
      );
      expect(
        p.validateForSubmit(adjustType: 'IN_ADJUST', unitCostRaw: '12.5'),
        isNull,
      );
    });

    test('costo explícito debe ser > 0', () {
      const p = InAdjustUnitCostPolicy(
        currentStockQuantity: 10,
        catalogUnitCost: '5',
      );
      expect(
        p.validateForSubmit(adjustType: 'IN_ADJUST', unitCostRaw: '0'),
        isNotNull,
      );
    });
  });
}
