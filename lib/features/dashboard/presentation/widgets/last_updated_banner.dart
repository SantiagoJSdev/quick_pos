import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';

class LastUpdatedBanner extends StatelessWidget {
  const LastUpdatedBanner({
    super.key,
    required this.updatedAt,
    this.offlineCache = false,
  });

  final DateTime? updatedAt;
  final bool offlineCache;

  @override
  Widget build(BuildContext context) {
    if (updatedAt == null) return const SizedBox.shrink();
    final t = updatedAt!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    final label = offlineCache
        ? 'Sin conexión — datos cacheados · $hh:$mm:$ss'
        : 'Actualizado $hh:$mm:$ss';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: offlineCache
          ? Colors.orange.withValues(alpha: 0.15)
          : PosSaleUi.surface3,
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: offlineCache ? Colors.orange : PosSaleUi.textMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
