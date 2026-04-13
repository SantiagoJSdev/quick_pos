import 'package:flutter/material.dart';

/// Estado de conectividad del [MainShell] para hijos (POS, inventario, etc.).
///
/// [isOnline]: operación normal contra backend (red + servidor + no forzado offline).
/// [manualForceOffline]: el usuario eligió «Poner Offline» hasta revertir en Inicio.
/// [backendReachable]: último resultado del health probe (sync automático no corre si
/// [manualForceOffline], pero el probe sigue para UX p. ej. banner en POS).
class ShellOnlineScope extends InheritedWidget {
  const ShellOnlineScope({
    super.key,
    required this.isOnline,
    this.manualForceOffline = false,
    this.backendReachable = true,
    required super.child,
  });

  final bool isOnline;
  final bool manualForceOffline;
  final bool backendReachable;

  /// Solo [isOnline] (compatibilidad).
  static bool of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ShellOnlineScope>();
    return s?.isOnline ?? true;
  }

  @override
  bool updateShouldNotify(covariant ShellOnlineScope oldWidget) =>
      oldWidget.isOnline != isOnline ||
      oldWidget.manualForceOffline != manualForceOffline ||
      oldWidget.backendReachable != backendReachable;
}
