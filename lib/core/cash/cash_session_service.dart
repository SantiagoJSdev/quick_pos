import '../api/api_error.dart';
import '../api/cash_sessions_api.dart';
import '../idempotency/client_mutation_id.dart';
import '../models/cash_session.dart';
import '../models/recent_sale_ticket.dart';
import '../pos/pos_terminal_info.dart';
import '../storage/local_prefs.dart';

/// Apertura explícita con fondo contado + helpers de cierre.
class CashSessionService {
  CashSessionService({
    required this.prefs,
    required this.api,
  });

  final LocalPrefs prefs;
  final CashSessionsApi api;

  Future<LocalCashSession?> loadOpenSession(String storeId) async {
    final terminal = await PosTerminalInfo.load(prefs);
    final session = await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: terminal.deviceId,
    );
    if (session == null || !session.isOpen) return null;
    return session;
  }

  /// True si este dispositivo ya tiene turno OPEN (puede entrar al POS).
  Future<bool> hasOpenSession(String storeId) async {
    final s = await loadOpenSession(storeId);
    return s != null;
  }

  /// Abre turno con [openingCashFunctional] (siempre moneda funcional, ej. USD).
  ///
  /// Online: `POST /cash-sessions` (si hay OPEN remota con fondo 0, pide actualizar;
  /// si fondo ≠ 0, error para cerrar primero).
  /// Offline: guarda OPEN local; Sync transmitirá después.
  Future<CashOpenResult> openCountedSession({
    required String storeId,
    required bool online,
    required String openingCashFunctional,
  }) async {
    final opening = openingCashFunctional.trim().replaceAll(',', '.');
    final parsed = double.tryParse(opening);
    if (parsed == null || parsed < 0) {
      return const CashOpenResult(
        ok: false,
        message: 'Ingresá un monto de apertura válido (≥ 0).',
      );
    }
    final openingNorm = parsed.toStringAsFixed(2);

    final terminal = await PosTerminalInfo.load(prefs);
    final deviceId = terminal.deviceId;

    final existing = await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: deviceId,
    );
    if (existing != null && existing.needsTransmit) {
      return const CashOpenResult(
        ok: false,
        message:
            'Hay un cierre pendiente de enviar. Sincronizá antes de abrir otro turno.',
      );
    }
    if (existing != null && existing.allowsPosSales) {
      return CashOpenResult(
        ok: true,
        alreadyOpen: true,
        session: existing,
        message: 'Ya hay un turno abierto.',
      );
    }

    final openedAt = DateTime.now().toUtc().toIso8601String();
    var local = LocalCashSession(
      localId: existing?.localId ?? ClientMutationId.newId(),
      storeId: storeId,
      deviceId: deviceId,
      status: LocalCashSession.statusOpen,
      transmitStatus: LocalCashSession.transmitSynced,
      openedAtIso: existing?.isOpen == true ? existing!.openedAtIso : openedAt,
      openingCash: openingNorm,
      remoteId: existing?.isOpen == true ? existing!.remoteId : null,
      openingCountedByUser: true,
    );

    if (!online) {
      await prefs.saveLocalCashSession(
        local.copyWith(clearRemoteId: true),
      );
      final saved = await prefs.loadLocalCashSession(
        storeId: storeId,
        deviceId: deviceId,
      );
      return CashOpenResult(
        ok: true,
        session: saved ?? local,
        offline: true,
        message:
            'Turno abierto sin internet. Vas a vender con los datos guardados '
            'en este teléfono. Sincronizá cuando haya red.',
      );
    }

    try {
      final current = await api.getCurrent(storeId, deviceId: deviceId);
      if (current != null && current.isOpen) {
        if (!LocalCashSession.isZeroOpeningCash(current.openingCash)) {
          // Turno real en servidor: no pisar.
          final linked = local.copyWith(
            remoteId: current.id,
            openingCash: current.openingCash ?? local.openingCash,
          );
          await prefs.saveLocalCashSession(linked);
          return CashOpenResult(
            ok: false,
            session: linked,
            message:
                'Hay un turno abierto en el servidor con fondo '
                '${current.openingCash}. Cerralo antes de abrir otro.',
          );
        }
        // Zombie openingCash 0: POST con fondo contado (backend debe actualizar).
      }

      // Contrato actual (CASH_SESSIONS.md): deviceId + openingCash + appVersion.
      // NO mandar clientOpenedAt hasta que el back lo acepte (pedido pendiente).
      final remote = await api.openSession(
        storeId,
        deviceId: deviceId,
        openingCash: openingNorm,
        appVersion: terminal.appVersion,
      );

      // Si el backend devolvió OPEN con fondo ≠ 0 distinto al pedido, no pisamos.
      if (!LocalCashSession.isZeroOpeningCash(remote.openingCash) &&
          remote.openingCash != null &&
          remote.openingCash!.trim().replaceAll(',', '.') != openingNorm) {
        final remoteAmt =
            double.tryParse(remote.openingCash!.replaceAll(',', '.')) ?? -1;
        if (remoteAmt > 0 && (remoteAmt - parsed).abs() > 0.001) {
          final linked = local.copyWith(
            remoteId: remote.id,
            openingCash: remote.openingCash,
          );
          await prefs.saveLocalCashSession(linked);
          return CashOpenResult(
            ok: false,
            session: linked,
            message:
                'Hay un turno abierto con fondo ${remote.openingCash}. '
                'Cerralo antes de abrir otro.',
          );
        }
      }

      final linked = local.copyWith(
        remoteId: remote.id,
        openingCash: openingNorm,
        transmitStatus: LocalCashSession.transmitSynced,
        openingCountedByUser: true,
      );
      await prefs.saveLocalCashSession(linked);
      return CashOpenResult(
        ok: true,
        session: linked,
        message: 'Turno abierto. Fondo: $openingNorm (moneda principal).',
      );
    } on ApiError catch (e) {
      return CashOpenResult(
        ok: false,
        message:
            'No se pudo abrir en el servidor (HTTP ${e.statusCode}).\n'
            '${e.userMessageForSupport}',
      );
    } catch (e) {
      return CashOpenResult(
        ok: false,
        message: 'No se pudo abrir en el servidor.\n$e',
      );
    }
  }

  /// Si hay OPEN local sin remoteId, intenta `POST /cash-sessions`.
  Future<bool> tryTransmitPendingOpen({
    required String storeId,
    required bool online,
  }) async {
    if (!online) return false;
    final terminal = await PosTerminalInfo.load(prefs);
    final session = await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: terminal.deviceId,
    );
    if (session == null || !session.needsOpenTransmit) return false;
    try {
      final current = await api.getCurrent(
        storeId,
        deviceId: terminal.deviceId,
      );
      if (current != null &&
          current.isOpen &&
          !LocalCashSession.isZeroOpeningCash(current.openingCash)) {
        // Ya hay turno real remoto: vincular sin pisar fondo.
        await prefs.saveLocalCashSession(
          session.copyWith(
            remoteId: current.id,
            openingCash: current.openingCash ?? session.openingCash,
          ),
        );
        return true;
      }
      final remote = await api.openSession(
        storeId,
        deviceId: terminal.deviceId,
        openingCash: session.openingCash,
        appVersion: terminal.appVersion,
      );
      await prefs.saveLocalCashSession(
        session.copyWith(remoteId: remote.id),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<PendingSaleCloseDeclaration>> pendingSalesDeclaration(
    String storeId,
  ) async {
    final pending = await prefs.loadPendingSales();
    final out = <PendingSaleCloseDeclaration>[];
    for (final e in pending) {
      if (e.storeId != storeId) continue;
      final saleId = e.sale['id']?.toString().trim() ?? '';
      if (saleId.isEmpty) continue;
      final total = e.sale['totalDocument']?.toString() ??
          e.sale['documentTotal']?.toString() ??
          '0';
      out.add(
        PendingSaleCloseDeclaration(
          saleId: saleId,
          opId: e.opId,
          total: total,
          createdAt: e.opTimestampIso,
        ),
      );
    }
    return out;
  }

  Future<LocalClosePreview> buildLocalPreview({
    required String storeId,
    required LocalCashSession session,
  }) async {
    final opened = DateTime.tryParse(session.openedAtIso)?.toLocal();
    final tickets = await prefs.loadRecentSaleTickets();
    var ticketCount = 0;
    double salesSumFunctional = 0;
    double salesSumDocument = 0;
    var hasFunctional = false;
    String? functionalCode;
    String? documentCode;
    for (final t in tickets) {
      if (t.storeId != storeId) continue;
      if (t.status == RecentSaleTicket.statusReturned) continue;
      final at = DateTime.tryParse(t.recordedAtIso)?.toLocal();
      if (opened != null && at != null && at.isBefore(opened)) continue;
      ticketCount++;
      documentCode ??= t.documentCurrencyCode;
      final docAmt =
          double.tryParse(t.totalDocument.replaceAll(',', '.')) ?? 0;
      salesSumDocument += docAmt;
      final tf = t.totalFunctional?.trim();
      if (tf != null && tf.isNotEmpty) {
        hasFunctional = true;
        functionalCode ??= t.functionalCurrencyCode ?? 'USD';
        salesSumFunctional +=
            double.tryParse(tf.replaceAll(',', '.')) ?? 0;
      }
    }
    final pending = await pendingSalesDeclaration(storeId);
    final inv = await prefs.loadInventoryCache(storeId);
    var negative = 0;
    for (final line in inv) {
      final q = line.quantityAsDouble ?? 0;
      if (q < 0) negative++;
    }
    final useFunc = hasFunctional;
    final code = useFunc
        ? (functionalCode ?? 'USD')
        : (documentCode ?? '');
    final amount = useFunc ? salesSumFunctional : salesSumDocument;
    return LocalClosePreview(
      ticketsCount: ticketCount,
      salesTotalDocumentApprox: amount.toStringAsFixed(2),
      salesCurrencyCode: code,
      salesPreferFunctional: useFunc,
      pendingSalesCount: pending.length,
      negativeSkuCount: negative,
      pendingSales: pending,
    );
  }

  /// Cierra en servidor (ONLINE). No abre sesión automáticamente.
  /// Si falla el POST, **no** guarda cierre local `pending_transmit`.
  Future<CashCloseResult> closeSession({
    required String storeId,
    required String countedCash,
    String? notes,
    LocalClosePreview? preview,
  }) async {
    final terminal = await PosTerminalInfo.load(prefs);
    final session = await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: terminal.deviceId,
    );
    if (session == null || !session.isOpen) {
      return const CashCloseResult(
        ok: false,
        message: 'No hay caja abierta. Abrí el turno antes de cerrar.',
      );
    }
    final remoteId = session.remoteId?.trim() ?? '';
    if (remoteId.isEmpty) {
      return const CashCloseResult(
        ok: false,
        message:
            'La apertura aún no está en el servidor. Tocá Sincronizar e intentá de nuevo.',
      );
    }

    final pending = preview?.pendingSales ??
        await pendingSalesDeclaration(storeId);

    try {
      final remoteSummary = await api.closeSession(
        storeId,
        remoteId,
        closeMode: 'ONLINE',
        countedCash: countedCash,
        pendingSales: pending,
        notes: notes,
      );
      final closed = session.copyWith(
        status: LocalCashSession.statusClosed,
        transmitStatus: LocalCashSession.transmitSynced,
        closedAtIso: DateTime.now().toUtc().toIso8601String(),
        countedCash: countedCash,
        closeMode: 'ONLINE',
        notes: notes,
      );
      await prefs.saveLocalCashSession(closed);
      return CashCloseResult(
        ok: true,
        message: 'Caja cerrada y enviada al servidor.',
        session: closed,
        remoteSummary: remoteSummary,
      );
    } on ApiError catch (e) {
      if (e.statusCode == 409) {
        // Ya cerrada en server.
        final closed = session.copyWith(
          status: LocalCashSession.statusClosed,
          transmitStatus: LocalCashSession.transmitSynced,
          closedAtIso: DateTime.now().toUtc().toIso8601String(),
          countedCash: countedCash,
          closeMode: 'ONLINE',
          notes: notes,
        );
        await prefs.saveLocalCashSession(closed);
        return CashCloseResult(
          ok: true,
          message: 'La caja ya estaba cerrada en el servidor.',
          session: closed,
        );
      }
      return CashCloseResult(
        ok: false,
        message: 'No se pudo cerrar en el servidor. La caja sigue abierta.\n'
            '${e.userMessage}',
        session: session,
      );
    } catch (e) {
      return CashCloseResult(
        ok: false,
        message: 'No se pudo cerrar en el servidor. La caja sigue abierta.\n$e',
        session: session,
      );
    }
  }

  /// Reintenta enviar un cierre `pending_transmit` viejo (migración Fase 1).
  Future<bool> tryTransmitPendingClose({
    required String storeId,
    required bool online,
  }) async {
    if (!online) return false;
    final terminal = await PosTerminalInfo.load(prefs);
    final session = await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: terminal.deviceId,
    );
    if (session == null || !session.needsTransmit) return false;
    var remoteId = session.remoteId;
    if (remoteId == null || remoteId.isEmpty) {
      return false;
    }
    final pending = await pendingSalesDeclaration(storeId);
    try {
      await api.closeSession(
        storeId,
        remoteId,
        closeMode: 'ONLINE',
        countedCash: session.countedCash ?? '0.00',
        pendingSales: pending,
        notes: session.notes ?? 'Cierre pendiente transmitido',
      );
      await prefs.saveLocalCashSession(
        session.copyWith(transmitStatus: LocalCashSession.transmitSynced),
      );
      return true;
    } on ApiError catch (e) {
      if (e.statusCode == 409) {
        await prefs.saveLocalCashSession(
          session.copyWith(transmitStatus: LocalCashSession.transmitSynced),
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}

class CashOpenResult {
  const CashOpenResult({
    required this.ok,
    required this.message,
    this.session,
    this.offline = false,
    this.alreadyOpen = false,
  });

  final bool ok;
  final String message;
  final LocalCashSession? session;
  final bool offline;
  final bool alreadyOpen;
}

class LocalClosePreview {
  const LocalClosePreview({
    required this.ticketsCount,
    required this.salesTotalDocumentApprox,
    required this.pendingSalesCount,
    required this.negativeSkuCount,
    required this.pendingSales,
    this.salesCurrencyCode = '',
    this.salesPreferFunctional = false,
  });

  final int ticketsCount;
  /// Monto de referencia (funcional si hay datos; si no, documento).
  final String salesTotalDocumentApprox;
  final String salesCurrencyCode;
  final bool salesPreferFunctional;
  final int pendingSalesCount;
  final int negativeSkuCount;
  final List<PendingSaleCloseDeclaration> pendingSales;

  String get salesTotalLabel {
    final c = salesCurrencyCode.trim();
    if (c.isEmpty) return salesTotalDocumentApprox;
    return '$salesTotalDocumentApprox $c';
  }
}

class CashCloseResult {
  const CashCloseResult({
    required this.ok,
    required this.message,
    this.session,
    this.remoteSummary,
    this.needsTransmit = false,
  });

  final bool ok;
  final String message;
  final LocalCashSession? session;
  final CashSessionSummaryResponse? remoteSummary;
  final bool needsTransmit;
}
