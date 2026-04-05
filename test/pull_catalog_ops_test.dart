import 'package:flutter_test/flutter_test.dart';
import 'package:quick_pos/core/sync/pull_catalog_ops.dart';

void main() {
  test('summarizePullOpsProductChanges detecta PRODUCT_* y productId', () {
    final ops = [
      {
        'serverVersion': 1,
        'opType': 'PRODUCT_UPDATED',
        'payload': {
          'productId': 'p-1',
          'fields': {'price': '1'},
        },
      },
      {
        'opType': 'SALE',
        'payload': {},
      },
      {
        'opType': 'PRODUCT_DEACTIVATED',
        'payload': {'productId': 'p-2'},
      },
    ];
    final s = summarizePullOpsProductChanges(ops);
    expect(s.hadMutation, true);
    expect(s.affectedProductIds, {'p-1', 'p-2'});
  });

  test('sin PRODUCT_* → hadMutation false', () {
    final s = summarizePullOpsProductChanges([
      {'opType': 'OTHER', 'payload': {}},
    ]);
    expect(s.hadMutation, false);
    expect(s.affectedProductIds, isEmpty);
  });
}
