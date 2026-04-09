import 'dart:io';

import 'package:http/http.dart' as http;

import '../api/api_error.dart';

/// Errores de transporte típicos (sin respuesta HTTP con cuerpo M0).
bool isLikelyNetworkFailure(Object error) {
  if (error is SocketException) return true;
  if (error is http.ClientException) return true;
  if (error is HandshakeException) return true;
  if (error is TlsException) return true;
  return false;
}

/// Cola local (catálogo, stock inicial, etc.): timeout, sin red o [ApiError] 408.
bool shouldTreatAsOfflineQueueable(Object error) {
  if (error is ApiError) return error.isLikelyTransportFailure;
  return isLikelyNetworkFailure(error);
}
