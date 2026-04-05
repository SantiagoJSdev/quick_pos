import 'package:flutter/material.dart';

import '../../features/sale/pos_sale_ui_tokens.dart';
import 'app_theme.dart';

/// Tema oscuro alineado al POS; usar en [MaterialApp] cuando hay tienda vinculada
/// para que rutas push y diálogos hereden los mismos colores.
class QuickMarketShellTheme {
  QuickMarketShellTheme._();

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppTheme.primaryOrange,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppTheme.primaryOrange,
      onPrimary: Colors.white,
      surface: PosSaleUi.surface,
      onSurface: PosSaleUi.text,
      onSurfaceVariant: PosSaleUi.textMuted,
      outline: PosSaleUi.border,
      outlineVariant: PosSaleUi.divider,
      error: PosSaleUi.error,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: PosSaleUi.bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: PosSaleUi.surface,
        foregroundColor: PosSaleUi.text,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: PosSaleUi.surface2,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: PosSaleUi.border),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: PosSaleUi.surface,
        indicatorColor: PosSaleUi.primaryDim,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
            color: sel ? PosSaleUi.primary : PosSaleUi.textMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final sel = states.contains(WidgetState.selected);
          return IconThemeData(
            color: sel ? PosSaleUi.primary : PosSaleUi.textMuted,
            size: 24,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(color: PosSaleUi.divider),
      dialogTheme: DialogThemeData(
        backgroundColor: PosSaleUi.surface2,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: PosSaleUi.surface3,
        contentTextStyle: const TextStyle(color: PosSaleUi.text),
        behavior: SnackBarBehavior.floating,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.primaryOrange,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: PosSaleUi.text,
          side: const BorderSide(color: PosSaleUi.border),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppTheme.primaryOrange,
        foregroundColor: Colors.white,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: PosSaleUi.textMuted,
        textColor: PosSaleUi.text,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: PosSaleUi.primary),
    );
  }
}
