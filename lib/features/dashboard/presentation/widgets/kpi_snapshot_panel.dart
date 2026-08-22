import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';
import '../../domain/kpi_snapshot.dart';
import '../dashboard_money_format.dart';

/// Tablero KPI snapshot — layout `docs/KPI_SNAPSHOT_FRONTEND.md` §2.
class KpiSnapshotPanel extends StatelessWidget {
  const KpiSnapshotPanel({
    super.key,
    required this.snapshot,
    required this.preset,
    required this.onPresetChanged,
    this.onRefresh,
  });

  final KpiSnapshot snapshot;
  final String preset;
  final ValueChanged<String> onPresetChanged;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final currency = snapshot.currencyCode;
    final real = snapshot.realProfit;
    final gross = snapshot.grossProfit;
    final debt = snapshot.payables;
    final stock = snapshot.stockAlerts;
    final showChart = preset == 'week' || preset == 'month';

    final content = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      children: [
        _PresetChips(preset: preset, onChanged: onPresetChanged),
        const SizedBox(height: 8),
        Text(
          snapshot.periodLabel,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PosSaleUi.textMuted,
              ),
        ),
        if (snapshot.timezoneIsFallbackUtc) ...[
          const SizedBox(height: 8),
          const _TimezoneFallbackBanner(),
        ],
        const SizedBox(height: 16),
        _RealProfitHero(real: real, currency: currency),
        const SizedBox(height: 12),
        if (snapshot.cashAvailable?.suggestedWithdraw != null)
          _SuggestedWithdrawChip(
            amount: snapshot.cashAvailable!.suggestedWithdraw!,
            currency: currency,
          ),
        if (snapshot.cashAvailable?.suggestedWithdraw != null)
          const SizedBox(height: 12),
        _GrossProfitCard(
          gross: gross,
          currency: currency,
          showChart: showChart,
        ),
        const SizedBox(height: 12),
        if (real?.deductions != null)
          _DeductionsExpansion(
            deductions: real!.deductions!,
            currency: currency,
            calendarDays: real.calendarDays,
          ),
        if (real?.deductions != null) const SizedBox(height: 12),
        if (real?.explain?.warnings.isNotEmpty == true) ...[
          _ExplainWarnings(warnings: real!.explain!.warnings),
          const SizedBox(height: 12),
        ],
        if (snapshot.capital != null) ...[
          _CapitalLiveCard(capital: snapshot.capital!, currency: currency),
          const SizedBox(height: 12),
        ],
        _PayablesCard(payables: debt, currency: currency),
        const SizedBox(height: 12),
        _StockAlertsCard(alerts: stock),
        const SizedBox(height: 12),
        Text(
          'La ganancia real no es “efectivo para sacar”. '
          'El chip de retiro usa suggestedWithdraw del servidor. '
          'Deuda, stock y capital live son snapshot actual (no siguen el período).',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PosSaleUi.textFaint,
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

class _PresetChips extends StatelessWidget {
  const _PresetChips({required this.preset, required this.onChanged});

  final String preset;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const items = [
      ('today', 'Hoy'),
      ('yesterday', 'Ayer'),
      ('week', 'Semana'),
      ('month', 'Mes'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final e in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(e.$2),
                selected: preset == e.$1,
                onSelected: (_) => onChanged(e.$1),
                selectedColor: PosSaleUi.primaryDim,
                labelStyle: TextStyle(
                  color: preset == e.$1 ? PosSaleUi.primary : PosSaleUi.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RealProfitHero extends StatelessWidget {
  const _RealProfitHero({required this.real, required this.currency});

  final KpiRealProfit? real;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final amount = real?.realProfit;
    final parsed = amount == null
        ? 0.0
        : DashboardMoneyFormat.chartValue(amount);
    final positive = parsed >= 0;
    final accent = positive ? PosSaleUi.success : const Color(0xFFE57373);
    final margin = real?.realMarginPercent;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Ganancia real',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: PosSaleUi.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if ((real?.phase ?? '').isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: PosSaleUi.surface3,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    real!.phase!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: PosSaleUi.textFaint,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            amount == null
                ? '—'
                : DashboardMoneyFormat.displayAmount(
                    amount,
                    currencyCode: currency,
                  ),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (margin != null && margin.trim().isNotEmpty)
                _MiniChip(
                  label: 'Margen real ${DashboardMoneyFormat.chartValue(margin).toStringAsFixed(1)}%',
                ),
              if (real?.calendarDays != null)
                _MiniChip(label: '${real!.calendarDays} días'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Después de empaque estimado, nómina y gastos fijos. '
            'No es efectivo disponible para retirar.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.textFaint,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _GrossProfitCard extends StatelessWidget {
  const _GrossProfitCard({
    required this.gross,
    required this.currency,
    required this.showChart,
  });

  final KpiGrossProfit? gross;
  final String currency;
  final bool showChart;

  @override
  Widget build(BuildContext context) {
    final gp = gross?.grossProfit;
    final margin = gross?.marginPercent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ganancia bruta',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: PosSaleUi.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            gp == null
                ? '—'
                : DashboardMoneyFormat.displayAmount(
                    gp,
                    currencyCode: currency,
                  ),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: PosSaleUi.text,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              if ((gross?.netSales ?? '').isNotEmpty)
                'Venta ${DashboardMoneyFormat.displayAmount(gross!.netSales!)}',
              if ((gross?.cogs ?? '').isNotEmpty)
                'Costo ${DashboardMoneyFormat.displayAmount(gross!.cogs!)}',
              if (margin != null && margin.trim().isNotEmpty)
                'Margen ${DashboardMoneyFormat.chartValue(margin).toStringAsFixed(1)}%',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.textFaint,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Antes de bolsas, personal y fijos.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.textFaint,
                ),
          ),
          if (showChart && (gross?.byDay.isNotEmpty ?? false)) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 72,
              child: _MiniBars(
                values: gross!.byDay
                    .map(
                      (d) => DashboardMoneyFormat.chartValue(
                        d.grossProfit ?? '0',
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.values});

  final List<double> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    final maxV = values.fold<double>(0, (a, b) => a > b.abs() ? a : b.abs());
    final scale = maxV <= 0 ? 1.0 : maxV;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final v in values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                height: 72 * (v.abs() / scale).clamp(0.05, 1.0),
                decoration: BoxDecoration(
                  color: v >= 0
                      ? PosSaleUi.primary.withValues(alpha: 0.75)
                      : Colors.redAccent.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            ),
          ),
      ],
    );
  }
}

class _DeductionsExpansion extends StatelessWidget {
  const _DeductionsExpansion({
    required this.deductions,
    required this.currency,
    this.calendarDays,
  });

  final KpiDeductions deductions;
  final String currency;
  final int? calendarDays;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(String title, String? amount, {String? detail}) {
      if (amount == null || amount.trim().isEmpty) return;
      rows.add(
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(title),
          subtitle: detail == null ? null : Text(detail),
          trailing: Text(
            DashboardMoneyFormat.displayAmount(amount, currencyCode: currency),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    final bags = deductions.bags;
    add(
      'Bolsas',
      bags?.amount,
      detail: [
        if ((bags?.tickets ?? '').isNotEmpty) '${bags!.tickets} tickets',
        if ((bags?.bagsEstimated ?? '').isNotEmpty)
          '~${bags!.bagsEstimated} bolsas',
      ].join(' · '),
    );
    final char = deductions.charcuterieWrap;
    add(
      'Platos charcutería',
      char?.amount,
      detail: [
        if ((char?.units ?? '').isNotEmpty) '${char!.units} u.',
        if ((char?.unitCost ?? '').isNotEmpty) '× ${char!.unitCost}',
      ].join(' '),
    );
    final pay = deductions.payroll;
    add(
      'Nómina',
      pay?.amount,
      detail: [
        if ((pay?.dailyTotal ?? '').isNotEmpty) '${pay!.dailyTotal}/día',
        if (pay?.days != null) '× ${pay!.days} d',
      ].join(' '),
    );
    for (final e in pay?.employees ?? const <KpiPayrollLine>[]) {
      if ((e.amount ?? '').isEmpty) continue;
      add('  · ${e.name ?? 'Empleado'}', e.amount);
    }
    final fixed = deductions.fixed;
    add('Fijos (luz/alquiler/transporte)', fixed?.amount);
    if ((fixed?.utilities ?? '').isNotEmpty) {
      add('  · Luz', fixed!.utilities);
    }
    if ((fixed?.rent ?? '').isNotEmpty) add('  · Alquiler', fixed!.rent);
    if ((fixed?.transport ?? '').isNotEmpty) {
      add('  · Transporte', fixed!.transport);
    }
    final losses = deductions.losses;
    add(
      'Merma',
      losses?.amount,
      detail: losses?.movementCount == null
          ? null
          : '${losses!.movementCount} mov.',
    );
    final commissions = deductions.paymentCommissions;
    add(
      'Comisiones de pago',
      commissions?.amount,
      detail: commissions?.paymentCount == null
          ? null
          : '${commissions!.paymentCount} pagos',
    );

    return Container(
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(
            'Deducciones',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          subtitle: Text(
            [
              if ((deductions.total ?? '').isNotEmpty)
                'Total ${DashboardMoneyFormat.displayAmount(deductions.total!, currencyCode: currency)}',
              if (calendarDays != null) '× $calendarDays días',
            ].join(' · '),
            style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 12),
          ),
          children: rows.isEmpty
              ? [
                  const Text(
                    'Sin detalle de deducciones en la respuesta.',
                    style: TextStyle(color: PosSaleUi.textFaint),
                  ),
                ]
              : rows,
        ),
      ),
    );
  }
}

class _PayablesCard extends StatelessWidget {
  const _PayablesCard({required this.payables, required this.currency});

  final KpiPayables? payables;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final total = payables?.totalDueFunctional;
    final aging = payables?.aging;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deuda a proveedores',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: PosSaleUi.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            total == null
                ? '—'
                : DashboardMoneyFormat.displayAmount(
                    total,
                    currencyCode: currency,
                  ),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PosSaleUi.text,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            [
              if (payables?.openInvoiceCount != null)
                '${payables!.openInvoiceCount} factura'
                    '${payables!.openInvoiceCount == 1 ? '' : 's'}',
              if ((payables?.asOf ?? '').isNotEmpty) 'Al ${payables!.asOf}',
            ].join(' · '),
            style: const TextStyle(color: PosSaleUi.textFaint, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _AgingChip(
                label: 'Vencida',
                bucket: aging?.overdue,
                currency: currency,
                color: Colors.redAccent,
              ),
              _AgingChip(
                label: 'Hoy',
                bucket: aging?.dueToday,
                currency: currency,
                color: Colors.orangeAccent,
              ),
              _AgingChip(
                label: '7 días',
                bucket: aging?.dueNext7Days,
                currency: currency,
                color: PosSaleUi.primary,
              ),
              _AgingChip(
                label: 'Luego',
                bucket: aging?.laterOrNoDueDate,
                currency: currency,
                color: PosSaleUi.textMuted,
              ),
            ],
          ),
          if (payables?.byDay.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text(
                  'Por vencimiento',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                children: [
                  for (final d in payables!.byDay.take(12))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        (d.date == null || d.date!.trim().isEmpty)
                            ? 'Sin vencimiento'
                            : d.date!,
                      ),
                      subtitle: d.invoiceCount == null
                          ? null
                          : Text('${d.invoiceCount} factura(s)'),
                      trailing: Text(
                        DashboardMoneyFormat.displayAmount(
                          d.amountDueFunctional ?? '0',
                          currencyCode: currency,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            'Snapshot actual · facturas crédito/parcial (no anuladas).',
            style: TextStyle(color: PosSaleUi.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _AgingChip extends StatelessWidget {
  const _AgingChip({
    required this.label,
    required this.bucket,
    required this.currency,
    required this.color,
  });

  final String label;
  final KpiAgingBucket? bucket;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final amount = bucket?.amountDueFunctional ?? '0';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DashboardMoneyFormat.displayAmount(amount, currencyCode: currency),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _StockAlertsCard extends StatelessWidget {
  const _StockAlertsCard({required this.alerts});

  final KpiStockAlerts? alerts;

  @override
  Widget build(BuildContext context) {
    final neg = alerts?.negativeCount ?? alerts?.negatives.length ?? 0;
    final low = alerts?.lowCount ?? alerts?.low.length ?? 0;
    final healthy = neg == 0 && low == 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Alertas de stock',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: PosSaleUi.textMuted,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          if (healthy)
            const Text(
              'Sin alertas — inventario sano.',
              style: TextStyle(color: PosSaleUi.success),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Badge(label: 'Negativos $neg', color: Colors.redAccent),
                _Badge(label: 'Bajos $low', color: Colors.orangeAccent),
              ],
            ),
          if (!healthy) ...[
            const SizedBox(height: 10),
            ...?(alerts?.negatives.take(8).map(
                  (i) => _StockRow(
                    item: i,
                    tone: Colors.redAccent,
                    kind: 'Negativo',
                  ),
                )),
            ...?(alerts?.low.take(8).map(
                  (i) => _StockRow(
                    item: i,
                    tone: Colors.orangeAccent,
                    kind: 'Bajo',
                  ),
                )),
            if ((alerts?.negatives.length ?? 0) + (alerts?.low.length ?? 0) > 16)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Mostrando primeras alertas…',
                  style: TextStyle(fontSize: 11, color: PosSaleUi.textFaint),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Text(
            'Negativo = disponible < 0. Bajo = bajo umbral'
            '${alerts?.defaultLowUnits == null ? '' : ' (${alerts!.defaultLowUnits} ud / ${alerts!.defaultLowKg ?? '—'} kg)'}.',
            style: const TextStyle(color: PosSaleUi.textFaint, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.item,
    required this.tone,
    required this.kind,
  });

  final KpiStockAlertItem item;
  final Color tone;
  final String kind;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(Icons.inventory_2_outlined, color: tone, size: 20),
      title: Text(item.name ?? item.sku ?? item.productId ?? 'Producto'),
      subtitle: Text(
        [
          kind,
          if ((item.sku ?? '').isNotEmpty) item.sku!,
          if ((item.available ?? '').isNotEmpty) 'disp. ${item.available}',
          if ((item.threshold ?? '').isNotEmpty) 'umbral ${item.threshold}',
        ].join(' · '),
        style: TextStyle(color: tone.withValues(alpha: 0.9), fontSize: 11),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: PosSaleUi.surface3,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: PosSaleUi.textMuted),
      ),
    );
  }
}

class _TimezoneFallbackBanner extends StatelessWidget {
  const _TimezoneFallbackBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'Zona horaria de respaldo (UTC). No confíes en Hoy/Ayer hasta '
        'configurar America/Caracas en la tienda.',
        style: TextStyle(color: Colors.orange, fontSize: 12, height: 1.35),
      ),
    );
  }
}

class _SuggestedWithdrawChip extends StatelessWidget {
  const _SuggestedWithdrawChip({
    required this.amount,
    required this.currency,
  });

  final String amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: PosSaleUi.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosSaleUi.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.payments_outlined, color: PosSaleUi.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Te puedes llevar hoy ~${DashboardMoneyFormat.displayAmount(amount, currencyCode: currency)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: PosSaleUi.text,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'suggestedWithdraw del servidor — no es la ganancia real',
                  style: TextStyle(fontSize: 11, color: PosSaleUi.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExplainWarnings extends StatelessWidget {
  const _ExplainWarnings({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Avisos del cálculo',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (final w in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '· $w',
                style: const TextStyle(
                  fontSize: 12,
                  color: PosSaleUi.textMuted,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CapitalLiveCard extends StatelessWidget {
  const _CapitalLiveCard({required this.capital, required this.currency});

  final KpiCapitalLive capital;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Patrimonio (ahora)',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            capital.netInventoryEquity == null
                ? '—'
                : DashboardMoneyFormat.displayAmount(
                    capital.netInventoryEquity!,
                    currencyCode: currency,
                  ),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            [
              if ((capital.inventoryCapital ?? '').isNotEmpty)
                'Inv. ${DashboardMoneyFormat.displayAmount(capital.inventoryCapital!, currencyCode: currency)}',
              if ((capital.payablesDue ?? '').isNotEmpty)
                'Deuda ${DashboardMoneyFormat.displayAmount(capital.payablesDue!, currencyCode: currency)}',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: PosSaleUi.textMuted),
          ),
          if ((capital.lossCostToday ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Merma hoy ${DashboardMoneyFormat.displayAmount(capital.lossCostToday!, currencyCode: currency)}'
              '${capital.lossMovementCountToday == null ? '' : ' · ${capital.lossMovementCountToday} mov.'}',
              style: const TextStyle(fontSize: 12, color: PosSaleUi.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}
