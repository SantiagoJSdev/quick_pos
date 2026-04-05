import 'dart:io';

import 'package:http/http.dart' as http;

/// Errores de transporte típicos (sin respuesta HTTP con cuerpo M0).
bool isLikelyNetworkFailure(Object error) {
  if (error is SocketException) return true;
  if (error is http.ClientException) return true;
  if (error is HandshakeException) return true;
  if (error is TlsException) return true;
  return false;
}
