import 'package:uuid/uuid.dart';

/// Identificadores de idempotencia en cliente (`opId`, `id` de venta, etc.).
///
/// Ver `docs/CLIENT_IDEMPOTENCY_AND_OFFLINE.md`: mismo valor en reintentos y,
/// más adelante, al reenviar desde cola offline / `sync/push`.
class ClientMutationId {
  ClientMutationId._();

  static final Uuid _uuid = Uuid();

  /// UUID v4 para una **operación lógica** (un envío concreto al API).
  static String newId() => _uuid.v4();
}
