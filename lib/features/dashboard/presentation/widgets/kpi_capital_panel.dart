import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';
import '../../domain/kpi_capital_series.dart';
import '../dashboard_money_format.dart';

/// Tab Capital — `docs/KPI_CONTRATO_FRONT.md` §4 / §8.
class KpiCapitalPanel extends StatelessWidget {
  const KpiCapitalPanel({
    super.key,
    required this.series,
    required this.preset,
    required this.onPresetChanged,
    required this.currencyCode,
    this.onRefresh,
  });

  final KpiCapitalSeries series;
  final String preset;
  final ValueChanged<String> onPresetChanged;
  final String currencyCode;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final latest = series.items.isEmpty ? null : series.items.last;
    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final e in const [('week', '7 días'), ('month', 'Mes')])
              ChoiceChip(
                label: Text(e.$2),
                selected: preset == e.$1,
                onSelected: (_) => onPresetChanged(e.$1),
                selectedColor: PosSaleUi.primaryDim,
                labelStyle: TextStyle(
                  color: preset == e.$1 ? PosSaleUi.primary : PosSaleUi.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          [
            if ((series.from ?? '').isNotEmpty && (series.to ?? '').isNotEmpty)
              '${series.from} → ${series.to}',
            currencyCode,
            if (series.lazyYesterday) 'ayer lazy',
          ].join(' · '),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PosSaleUi.textMuted,
              ),
        ),
        const SizedBox(height: 16),
        _EquityHero(latest: latest, currency: currencyCode),
        if (series.missingDates.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Días sin foto (${series.missingDates.length}): '
              '${series.missingDates.length <= 5 ? series.missingDates.join(', ') : '${series.missingDates.take(5).join(', ')}…'}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.amber,
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Serie de patrimonio',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        if (series.items.isEmpty)
          const Text(
            'Sin fotos de capital en el rango.',
            style: TextStyle(color: PosSaleUi.textFaint),
          )
        else
          ...series.items.reversed.map(
            (e) => _CapitalDayTile(item: e, currency: currencyCode),
          ),
        const SizedBox(height: 12),
        const Text(
          'No se inventan puntos: los huecos van en missingDates. '
          'deltaEquity null = sin flecha.',
          style: TextStyle(
            color: PosSaleUi.textFaint,
            fontSize: 12,
            height: 1.35,
          ),
        ),
      ],
    );

    if (onRefresh == null) return content;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: PosSaleUi.primary,
      child: content,
    );
  }
}

class _EquityHero extends StatelessWidget {
  const _EquityHero({required this.latest, required this.currency});

  final KpiCapitalSeriesItem? latest;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final equity = latest?.netInventoryEquity;
    final delta = latest?.deltaEquity;
    final deltaN =
        delta == null ? null : double.tryParse(delta.replaceAll(',', '.'));
    final deltaColor = deltaN == null
        ? PosSaleUi.textMuted
        : (deltaN >= 0 ? const Color(0xFF66BB6A) : const Color(0xFFE57373));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patrimonio neto',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: PosSaleUi.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            equity == null
                ? '—'
                : DashboardMoneyFormat.displayAmount(
                    equity,
                    currencyCode: currency,
                  ),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 8),
          if (delta != null)
            Text(
              'Δ vs día anterior: ${DashboardMoneyFormat.displayAmount(delta, currencyCode: currency)}',
              style: TextStyle(
                color: deltaColor,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            )
          else
            const Text(
              'Sin Δ (falta foto del día anterior)',
              style: TextStyle(color: PosSaleUi.textFaint, fontSize: 12),
            ),
          if ((latest?.date ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Foto ${latest!.date}${latest!.source == null ? '' : ' · ${latest!.source}'}',
              style: const TextStyle(color: PosSaleUi.textFaint, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _CapitalDayTile extends StatelessWidget {
  const _CapitalDayTile({required this.item, required this.currency});

  final KpiCapitalSeriesItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final delta = item.deltaEquity;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(item.date, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        [
          if ((item.inventoryCapital ?? '').isNotEmpty)
            'Inv ${DashboardMoneyFormat.displayAmount(item.inventoryCapital!)}',
          if ((item.payablesDue ?? '').isNotEmpty)
            'Deuda ${DashboardMoneyFormat.displayAmount(item.payablesDue!)}',
          if ((item.realProfit ?? '').isNotEmpty)
            'Real ${DashboardMoneyFormat.displayAmount(item.realProfit!)}',
        ].join(' · '),
        style: const TextStyle(fontSize: 11, color: PosSaleUi.textMuted),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            item.netInventoryEquity == null
                ? '—'
                : DashboardMoneyFormat.displayAmount(
                    item.netInventoryEquity!,
                    currencyCode: currency,
                  ),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (delta != null)
            Text(
              'Δ $delta',
              style: const TextStyle(fontSize: 11, color: PosSaleUi.textFaint),
            ),
        ],
      ),
    );
  }
}
