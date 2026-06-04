import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';
import '../../domain/payment_breakdown_item.dart';
import '../dashboard_money_format.dart';
import '../payment_method_labels.dart';

class PaymentsBreakdownList extends StatelessWidget {
  const PaymentsBreakdownList({
    super.key,
    required this.items,
    required this.currencyCode,
  });

  final List<PaymentBreakdownItem> items;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        color: PosSaleUi.surface2,
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Sin desglose de pagos en el período',
            style: TextStyle(color: PosSaleUi.textMuted),
          ),
        ),
      );
    }

    var total = 0.0;
    for (final it in items) {
      total += DashboardMoneyFormat.chartValue(it.amount);
    }
    if (total <= 0) total = 1;

    return Card(
      margin: EdgeInsets.zero,
      color: PosSaleUi.surface2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pagos por método',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: PosSaleUi.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            for (final it in items) ...[
              _PaymentRow(
                label: paymentMethodLabel(it.method),
                amount: DashboardMoneyFormat.displayAmount(
                  it.amount,
                  currencyCode: currencyCode,
                ),
                fraction: DashboardMoneyFormat.chartValue(it.amount) / total,
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.amount,
    required this.fraction,
  });

  final String label;
  final String amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: PosSaleUi.text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              amount,
              style: const TextStyle(
                color: PosSaleUi.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction.clamp(0, 1),
            minHeight: 6,
            backgroundColor: PosSaleUi.surface4,
            color: PosSaleUi.primary,
          ),
        ),
      ],
    );
  }
}
