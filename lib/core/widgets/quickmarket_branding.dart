import 'package:flutter/material.dart';

import '../../features/sale/pos_sale_ui_tokens.dart';

/// Ícono en recuadro naranja (marca POS).
class QuickMarketLogoMark extends StatelessWidget {
  const QuickMarketLogoMark({
    super.key,
    this.size = 28,
    this.borderRadius = 8,
    this.icon = Icons.shopping_cart_outlined,
    this.iconSize,
  });

  final double size;
  final double borderRadius;
  final IconData icon;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final s = iconSize ?? (size * 0.57).clamp(14.0, 22.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: PosSaleUi.primary,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(icon, color: Colors.white, size: s),
    );
  }
}

/// Misma wordmark que [PosSaleTopBar]: **Quick** + **Market** (naranja).
class QuickMarketWordmark extends StatelessWidget {
  const QuickMarketWordmark({
    super.key,
    this.logoSize = 28,
    this.fontSize = 14,
    this.gap = 8,
    this.icon = Icons.shopping_cart_outlined,
  });

  final double logoSize;
  final double fontSize;
  final double gap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        QuickMarketLogoMark(size: logoSize, icon: icon),
        SizedBox(width: gap),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: PosSaleUi.text,
              letterSpacing: -0.2,
            ),
            children: const [
              TextSpan(text: 'Quick'),
              TextSpan(
                text: 'Market',
                style: TextStyle(color: PosSaleUi.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Cabecera de página tipo menú Ventas: módulo + **QuickMarket** + subtítulo.
class QuickMarketModuleHeader extends StatelessWidget {
  const QuickMarketModuleHeader({
    super.key,
    required this.moduleLabel,
    this.subtitle,
    this.logoSize = 40,
    this.titleFontSize = 20,
  });

  final String moduleLabel;
  final String? subtitle;
  final double logoSize;
  final double titleFontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        QuickMarketLogoMark(size: logoSize, borderRadius: 12),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: titleFontSize,
                    fontWeight: FontWeight.w800,
                    color: PosSaleUi.text,
                  ),
                  children: [
                    TextSpan(text: moduleLabel),
                    TextSpan(
                      text: ' QuickMarket',
                      style: const TextStyle(
                        color: PosSaleUi.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: PosSaleUi.textMuted,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
