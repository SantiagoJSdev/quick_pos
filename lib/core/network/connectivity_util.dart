import 'package:connectivity_plus/connectivity_plus.dart';

/// `connectivity_plus`: sin red suele ser `[ConnectivityResult.none]`.
bool connectivityAppearsOnline(List<ConnectivityResult> results) {
  return results.any((e) => e != ConnectivityResult.none);
}

/// Transición típica “recuperé red” (evita spurious en el primer evento).
bool connectivityTransitionedToOnline(
  List<ConnectivityResult>? previous,
  List<ConnectivityResult> next,
) {
  if (previous == null) return false;
  return !connectivityAppearsOnline(previous) &&
      connectivityAppearsOnline(next);
}
