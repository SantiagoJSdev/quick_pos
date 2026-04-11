import 'package:flutter/material.dart';

/// Estado online/offline global del [MainShell]. Las rutas empujadas en un
/// [Navigator] anidado no reciben props actualizadas; con este [InheritedWidget]
/// leen el valor actual y se reconstruyen al cambiar.
class ShellOnlineScope extends InheritedWidget {
  const ShellOnlineScope({
    super.key,
    required this.isOnline,
    required super.child,
  });

  final bool isOnline;

  static bool of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<ShellOnlineScope>();
    return s?.isOnline ?? true;
  }

  @override
  bool updateShouldNotify(covariant ShellOnlineScope oldWidget) =>
      oldWidget.isOnline != isOnline;
}
