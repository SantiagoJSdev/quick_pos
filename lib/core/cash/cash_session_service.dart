import '../api/api_error.dart';
import '../api/cash_sessions_api.dart';
import '../idempotency/client_mutation_id.dart';
import '../models/cash_session.dart';
import '../pos/pos_terminal_info.dart';
import '../storage/local_prefs.dart';

/// Apertura automática (sin UI de fondo) + helpers de cierre.
class CashSessionService {
  CashSessionService({
    required this.prefs,
    required this.api,
  });

  final LocalPrefs prefs;
  final CashSessionsApi api;

  /// Garantiza sesión OPEN local. Si hay red, sincroniza con `POST /cash-sessions`
  /// (`openingCash: 0.00` — sin pantalla de apertura).
  Future<LocalCashSession> ensureOpenSession({
    required String storeId,
    required bool online,
  }) async {
    final terminal = await PosTerminalInfo.load(prefs);
    final deviceId = terminal.deviceId;
    final existing = await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: deviceId,
    );
    if (existing != null && existing.isOpen) {
      if (online && (existing.remoteId == null || existing.remoteId!.isEmpty)) {
        return _linkOrOpenRemote(existing, terminal.appVersion, online: online);
      }
      return existing;
    }

    // Sesión cerrada pendiente de transmitir: no abrir otra hasta resolver.
    if (existing != null && existing.needsTransmit) {
      return existing;
    }

    final local = LocalCashSession(
      localId: ClientMutationId.newId(),
      storeId: storeId,
      deviceId: deviceId,
      status: LocalCashSession.statusOpen,
      transmitStatus: LocalCashSession.transmitSynced,
      openedAtIso: DateTime.now().toUtc().toIso8601String(),
      openingCash: '0.00',
    );

    if (!online) {
      await prefs.saveLocalCashSession(local);
      return local;
    }

    return _linkOrOpenRemote(local, terminal.appVersion, online: true);
  }

  Future<LocalCashSession> _linkOrOpenRemote(
    LocalCashSession local,
    String appVersion, {
    required bool online,
  }) async {
    if (!online) {
      await prefs.saveLocalCashSession(local);
      return local;
    }
    try {
      final current = await api.getCurrent(
        local.storeId,
        deviceId: local.deviceId,
      );
      final remote = current ??
          await api.openSession(
            local.storeId,
            deviceId: local.deviceId,
            openingCash: local.openingCash,
            appVersion: appVersion,
          );
      final linked = local.copyWith(
        remoteId: remote.id,
        transmitStatus: LocalCashSession.transmitSynced,
      );
      await prefs.saveLocalCashSession(linked);
      return linked;
    } on ApiError {
      await prefs.saveLocalCashSession(local);
      return local;
    } catch (_) {
      await prefs.saveLocalCashSession(local);
      return local;
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
    double salesSum = 0;
    for (final t in tickets) {
      if (t.storeId != storeId) continue;
      final at = DateTime.tryParse(t.recordedAtIso)?.toLocal();
      if (opened != null && at != null && at.isBefore(opened)) continue;
      ticketCount++;
      salesSum += double.tryParse(t.totalDocument.replaceAll(',', '.')) ?? 0;
    }
    final pending = await pendingSalesDeclaration(storeId);
    final inv = await prefs.loadInventoryCache(storeId);
    var negative = 0;
    for (final line in inv) {
      final q = line.quantityAsDouble ?? 0;
      if (q < 0) negative++;
    }
    return LocalClosePreview(
      ticketsCount: ticketCount,
      salesTotalDocumentApprox: salesSum.toStringAsFixed(2),
      pendingSalesCount: pending.length,
      negativeSkuCount: negative,
      pendingSales: pending,
    );
  }

  /// Cierra en local y, si hay red + remoteId, llama `POST .../close`.
  Future<CashCloseResult> closeSession({
    required String storeId,
    required bool online,
    required String countedCash,
    String? notes,
    LocalClosePreview? preview,
  }) async {
    final terminal = await PosTerminalInfo.load(prefs);
    var session = await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: terminal.deviceId,
    );
    if (session == null || !session.isOpen) {
      if (online) {
        session = await ensureOpenSession(storeId: storeId, online: true);
      }
    }
    session ??= await prefs.loadLocalCashSession(
      storeId: storeId,
      deviceId: terminal.deviceId,
    );
    if (session == null || !session.isOpen) {
      return const CashCloseResult(
        ok: false,
        message: 'No hay caja abierta en este dispositivo.',
      );
    }
    var openSession = session;

    final pending = preview?.pendingSales ??
        await pendingSalesDeclaration(storeId);
    final closeMode = online &&
            openSession.remoteId != null &&
            openSession.remoteId!.trim().isNotEmpty
        ? 'ONLINE'
        : 'OFFLINE';

    CashSessionSummaryResponse? remoteSummary;
    var transmit = LocalCashSession.transmitSynced;
    String? message;

    if (closeMode == 'ONLINE') {
      try {
        remoteSummary = await api.closeSession(
          storeId,
          openSession.remoteId!,
          closeMode: 'ONLINE',
          countedCash: countedCash,
          pendingSales: pending,
          notes: notes,
        );
        transmit = LocalCashSession.transmitSynced;
        message = 'Caja cerrada y enviada al servidor.';
      } catch (e) {
        transmit = LocalCashSession.transmitPending;
        message =
            'Caja cerrada en el dispositivo. Pendiente transmitir: $e';
      }
    } else {
      transmit = LocalCashSession.transmitPending;
      message =
          'Caja cerrada · pendiente transmitir (sin red o sin sesión remota).';
      if (online &&
          (openSession.remoteId == null ||
              openSession.remoteId!.trim().isEmpty)) {
        try {
          final linked = await _linkOrOpenRemote(
            openSession,
            terminal.appVersion,
            online: true,
          );
          openSession = linked;
          if (linked.remoteId != null && linked.remoteId!.isNotEmpty) {
            remoteSummary = await api.closeSession(
              storeId,
              linked.remoteId!,
              closeMode: online ? 'ONLINE' : 'OFFLINE',
              countedCash: countedCash,
              pendingSales: pending,
              notes: notes,
            );
            transmit = LocalCashSession.transmitSynced;
            message = 'Caja cerrada y enviada al servidor.';
          }
        } catch (_) {
          transmit = LocalCashSession.transmitPending;
        }
      } else if (online && openSession.remoteId != null) {
        try {
          remoteSummary = await api.closeSession(
            storeId,
            openSession.remoteId!,
            closeMode: 'OFFLINE',
            countedCash: countedCash,
            pendingSales: pending,
            notes: notes,
          );
          transmit = LocalCashSession.transmitSynced;
          message = 'Caja cerrada (modo OFFLINE declarado) en el servidor.';
        } catch (e) {
          transmit = LocalCashSession.transmitPending;
          message = 'Caja cerrada localmente · pendiente transmitir: $e';
        }
      }
    }

    final closed = openSession.copyWith(
      status: LocalCashSession.statusClosed,
      transmitStatus: transmit,
      closedAtIso: DateTime.now().toUtc().toIso8601String(),
      countedCash: countedCash,
      closeMode: closeMode,
      notes: notes,
    );
    await prefs.saveLocalCashSession(closed);

    return CashCloseResult(
      ok: true,
      message: message ?? 'Caja cerrada.',
      session: closed,
      remoteSummary: remoteSummary,
      needsTransmit: transmit == LocalCashSession.transmitPending,
    );
  }

  /// Reintenta enviar un cierre `pending_transmit` si hay red.
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
    final pending = await pendingSalesDeclaration(storeId);
    var remoteId = session.remoteId;
    if (remoteId == null || remoteId.isEmpty) {
      try {
        final linked = await _linkOrOpenRemote(
          session.copyWith(status: LocalCashSession.statusOpen),
          terminal.appVersion,
          online: true,
        );
        // Si ya estaba closed, abrimos remota solo para poder cerrar declaración —
        // mejor: open current or open then close with OFFLINE.
        remoteId = linked.remoteId;
      } catch (_) {
        return false;
      }
    }
    if (remoteId == null || remoteId.isEmpty) return false;
    try {
      await api.closeSession(
        storeId,
        remoteId,
        closeMode: 'OFFLINE',
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
        // Ya cerrada en server.
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

class LocalClosePreview {
  const LocalClosePreview({
    required this.ticketsCount,
    required this.salesTotalDocumentApprox,
    required this.pendingSalesCount,
    required this.negativeSkuCount,
    required this.pendingSales,
  });

  final int ticketsCount;
  final String salesTotalDocumentApprox;
  final int pendingSalesCount;
  final int negativeSkuCount;
  final List<PendingSaleCloseDeclaration> pendingSales;
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
