import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/sync/inventory_adjust_payload_builder.dart';

void main() {
  test('toRestBody incluye opId y unitCostFunctional opcional', () {
    final b = InventoryAdjustPayloadBuilder.fromForm(
      productId: 'p1',
      type: 'IN_ADJUST',
      quantity: '5',
      reason: 'conteo',
      unitCostFunctional: '2.5',
    );
    final rest = b.toRestBody(opId: 'oid-1');
    expect(rest['opId'], 'oid-1');
    expect(rest['productId'], 'p1');
    expect(rest['unitCostFunctional'], '2.5');
  });

  test('toSyncPayload usa inventoryAdjust sin opId', () {
    final b = InventoryAdjustPayloadBuilder.fromForm(
      productId: 'p1',
      type: 'OUT_ADJUST',
      quantity: '1',
      reason: 'merma',
    );
    final sync = b.toSyncPayload();
    expect(sync.containsKey('inventoryAdjust'), true);
    final inner = sync['inventoryAdjust'] as Map<String, dynamic>;
    expect(inner['productId'], 'p1');
    expect(inner['type'], 'OUT_ADJUST');
    expect(inner.containsKey('opId'), false);
  });
}
