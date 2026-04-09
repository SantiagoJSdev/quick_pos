import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Tokens visuales alineados a `docs/quickmarket-pos.html` (tema oscuro POS).
class PosSaleUi {
  PosSaleUi._();

  static const Color bg = Color(0xFF111210);
  static const Color surface = Color(0xFF191918);
  static const Color surface2 = Color(0xFF1E1E1C);
  static const Color surface3 = Color(0xFF252523);
  static const Color surface4 = Color(0xFF2C2C2A);
  static const Color divider = Color(0xFF2F2F2D);
  static const Color border = Color(0xFF383836);
  static const Color text = Color(0xFFE8E7E4);
  static const Color textMuted = Color(0xFF888784);
  static const Color textFaint = Color(0xFF555452);
  static const Color gold = Color(0xFFE8C34A);
  static const Color goldDim = Color(0x1FE8C34A);
  static const Color error = Color(0xFFE05252);
  static const Color success = Color(0xFF5AAB3E);

  /// Marca documentada (#FF6D00).
  static const Color primary = AppTheme.primaryOrange;
  static const Color primaryDim = Color(0x26FF6D00);

  /// Fondo del desplegable de sugerencias de búsqueda (tinte naranja suave sobre tema oscuro).
  static const Color searchSuggestionsSurface = Color(0xFF2E2618);

  static TextStyle titleCart(BuildContext context) => const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.7,
        color: textMuted,
      );
}
