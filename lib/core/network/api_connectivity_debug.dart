import 'package:flutter/foundation.dart';

/// Traza en consola / Logcat (solo [kDebugMode]) el encadenamiento Vercel → API.
void traceApiConnectivity(String message) {
  if (kDebugMode) {
    debugPrint('[QuickPos:API] $message');
  }
}
