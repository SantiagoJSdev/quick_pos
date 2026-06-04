import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';

class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.accentColor,
  });

  final String title;
  final String value;
  final String? subtitle;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? PosSaleUi.text;
    return Card(
      margin: EdgeInsets.zero,
      color: PosSaleUi.surface2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: PosSaleUi.textMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.textFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
