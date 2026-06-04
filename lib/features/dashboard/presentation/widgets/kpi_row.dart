import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';
import '../../data/dashboard_repository.dart';
import '../dashboard_money_format.dart';
import 'kpi_card.dart';

class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.data});

  final DashboardHomeData data;

  @override
  Widget build(BuildContext context) {
    final s = data.summary;
    final cur = s.currencyCode;
    final rate = DashboardMoneyFormat.displayReturnRate(s.returnRate);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 520;
        final cards = [
          KpiCard(
            title: 'Ventas netas',
            value: DashboardMoneyFormat.displayAmount(s.netSales, currencyCode: cur),
            accentColor: PosSaleUi.success,
          ),
          KpiCard(
            title: 'Ventas brutas',
            value: DashboardMoneyFormat.displayAmount(s.grossSales, currencyCode: cur),
          ),
          KpiCard(
            title: 'Devoluciones',
            value: DashboardMoneyFormat.displayAmount(s.returns, currencyCode: cur),
            accentColor: const Color(0xFFE8A34A),
          ),
          KpiCard(
            title: 'Tickets',
            value: '${s.tickets}',
          ),
          KpiCard(
            title: 'Ticket promedio',
            value: DashboardMoneyFormat.displayAmount(s.avgTicket, currencyCode: cur),
          ),
          if (rate != null)
            KpiCard(
              title: 'Tasa devolución',
              value: rate,
            ),
        ];

        if (wide) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: cards
                .map(
                  (c) => SizedBox(
                    width: (constraints.maxWidth - 24) / 3,
                    child: c,
                  ),
                )
                .toList(),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              cards[i],
            ],
          ],
        );
      },
    );
  }
}
