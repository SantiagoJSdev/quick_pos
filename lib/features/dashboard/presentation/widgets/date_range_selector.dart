import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';
import '../../domain/dashboard_filters.dart';

typedef OnFiltersChanged = void Function(DashboardFilters filters);

class DateRangeSelector extends StatelessWidget {
  const DateRangeSelector({
    super.key,
    required this.current,
    required this.onChanged,
    this.onCustomRange,
  });

  final DashboardFilters current;
  final OnFiltersChanged onChanged;
  final Future<({String from, String to})?> Function()? onCustomRange;

  @override
  Widget build(BuildContext context) {
    final isCustom =
        current.preset == null &&
        current.dateFrom != null &&
        current.dateTo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in DashboardPreset.values)
              FilterChip(
                label: Text(p.label),
                selected: current.preset == p,
                onSelected: (_) => onChanged(DashboardFilters(preset: p)),
                selectedColor: PosSaleUi.primaryDim,
                checkmarkColor: PosSaleUi.primary,
              ),
            FilterChip(
              label: const Text('Personalizado'),
              selected: isCustom,
              onSelected: (_) async {
                final picker = onCustomRange;
                if (picker == null) return;
                final range = await picker();
                if (range == null) return;
                onChanged(
                  DashboardFilters(
                    dateFrom: range.from,
                    dateTo: range.to,
                  ),
                );
              },
              selectedColor: PosSaleUi.primaryDim,
              checkmarkColor: PosSaleUi.primary,
            ),
          ],
        ),
      ],
    );
  }
}
