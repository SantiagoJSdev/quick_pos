import 'package:flutter/foundation.dart';

/// Traza en consola / Logcat (solo [kDebugMode]) para diagnóstico de API / conectividad.
void traceApiConnectivity(String message) {
  if (kDebugMode) {
    debugPrint('[QuickPos:API] $message');
  }
}
