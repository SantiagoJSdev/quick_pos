import 'package:flutter/material.dart';

/// Material 3 — primary naranja marca (#FF6D00) según guía del proyecto.
class AppTheme {
  AppTheme._();

  static const Color primaryOrange = Color(0xFFFF6D00);
  static const Color primaryContainer = Color(0xFFFFCCAA);
  static const Color secondaryBlueGrey = Color(0xFF455A64);
  static const Color tertiaryTeal = Color(0xFF00695C);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryOrange,
      primary: primaryOrange,
      onPrimary: Colors.white,
      primaryContainer: primaryContainer,
      secondary: secondaryBlueGrey,
      tertiary: tertiaryTeal,
      surface: const Color(0xFFF8F9FA),
      error: const Color(0xFFB3261E),
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
      ),
    );
  }
}
