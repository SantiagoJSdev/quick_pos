import 'package:flutter/material.dart';

/// Estado de conectividad del [MainShell] para hijos (POS, inventario, etc.).
///
/// [isOnline]: operación normal contra backend (red + servidor + no forzado offline).
/// [manualForceOffline]: el usuario eligió «Poner Offline» hasta revertir en Inicio.
/// [backendReachable]: último resultado conocido del servidor (gesto Sync /
/// Poner Online / fallo de transporte). Sin probe periódico en segundo plano.
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
