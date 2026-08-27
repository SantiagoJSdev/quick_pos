/// Modelos de sesión de caja (B2 / `docs/CASH_SESSIONS.md`).
class CashSessionInfo {
  const CashSessionInfo({
    required this.id,
    required this.status,
    required this.deviceId,
    this.openedAt,
    this.closedAt,
    this.openingCash,
  });

  final String id;
  final String status;
  final String deviceId;
  final String? openedAt;
  final String? closedAt;
  final String? openingCash;

  bool get isOpen => status.toUpperCase() == 'OPEN';
  bool get isClosed => status.toUpperCase() == 'CLOSED';

  static CashSessionInfo? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id']?.toString().trim() ?? '';
    final deviceId = json['deviceId']?.toString().trim() ?? '';
    final status = json['status']?.toString().trim() ?? '';
    if (id.isEmpty || deviceId.isEmpty || status.isEmpty) return null;
    return CashSessionInfo(
      id: id,
      status: status,
      deviceId: deviceId,
      openedAt: json['openedAt']?.toString(),
      closedAt: json['closedAt']?.toString(),
      openingCash: json['openingCash']?.toString(),
    );
  }
}

class CashSessionSummaryBlock {
  const CashSessionSummaryBlock({
    this.openedAt,
    this.closedAt,
    this.ticketsCount,
    this.salesTotalFunctional,
    this.returnsTotalFunctional,
    this.netSalesFunctional,
    this.stockConflictSalesCount,
    this.negativeSkuCount,
    this.syncFailedCount,
    this.pendingCountDeclared,
  });

  final String? openedAt;
  final String? closedAt;
  final int? ticketsCount;
  final String? salesTotalFunctional;
  final String? returnsTotalFunctional;
  final String? netSalesFunctional;
  final int? stockConflictSalesCount;
  final int? negativeSkuCount;
  final int? syncFailedCount;
  final int? pendingCountDeclared;

  static CashSessionSummaryBlock fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) {
      if (v is int) return v;
      return int.tryParse(v?.toString() ?? '');
    }

    return CashSessionSummaryBlock(
      openedAt: json['openedAt']?.toString(),
      closedAt: json['closedAt']?.toString(),
      ticketsCount: asInt(json['ticketsCount']),
      salesTotalFunctional: json['salesTotalFunctional']?.toString(),
      returnsTotalFunctional: json['returnsTotalFunctional']?.toString(),
      netSalesFunctional: json['netSalesFunctional']?.toString(),
      stockConflictSalesCount: asInt(json['stockConflictSalesCount']),
      negativeSkuCount: asInt(json['negativeSkuCount']),
      syncFailedCount: asInt(json['syncFailedCount']),
      pendingCountDeclared: asInt(json['pendingCountDeclared']),
    );
  }
}

class CashSessionSummaryResponse {
  const CashSessionSummaryResponse({
    required this.session,
    required this.summary,
    this.warnings = const [],
    this.requireSuccessfulSyncAtClose = false,
    this.capitalPhoto,
  });

  final CashSessionInfo session;
  final CashSessionSummaryBlock summary;
  final List<String> warnings;
  final bool requireSuccessfulSyncAtClose;
  final CashCapitalPhoto? capitalPhoto;

  static CashSessionSummaryResponse? tryFromJson(Map<String, dynamic> json) {
    final session = CashSessionInfo.tryFromJson(
      json['session'] is Map
          ? Map<String, dynamic>.from(json['session'] as Map)
          : null,
    );
    final rawSummary = json['summary'];
    if (session == null || rawSummary is! Map) return null;
    final warnings = <String>[];
    final w = json['warnings'];
    if (w is List) {
      for (final e in w) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) warnings.add(s);
      }
    }
    return CashSessionSummaryResponse(
      session: session,
      summary: CashSessionSummaryBlock.fromJson(
        Map<String, dynamic>.from(rawSummary),
      ),
      warnings: warnings,
      requireSuccessfulSyncAtClose: json['requireSuccessfulSyncAtClose'] == true,
      capitalPhoto: CashCapitalPhoto.tryFromJson(
        json['capitalPhoto'] is Map
            ? Map<String, dynamic>.from(json['capitalPhoto'] as Map)
            : null,
      ),
    );
  }
}

/// Foto de patrimonio al cerrar caja — `docs/KPI_CONTRATO_FRONT.md` §7.
class CashCapitalPhoto {
  const CashCapitalPhoto({
    this.date,
    this.ok = false,
    this.netInventoryEquity,
  });

  final String? date;
  final bool ok;
  final String? netInventoryEquity;

  static CashCapitalPhoto? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return CashCapitalPhoto(
      date: json['date']?.toString(),
      ok: json['ok'] == true,
      netInventoryEquity: json['netInventoryEquity']?.toString(),
    );
  }
}

/// Copia local de la sesión de caja del dispositivo.
class LocalCashSession {
  const LocalCashSession({
    required this.localId,
    required this.storeId,
    required this.deviceId,
    required this.status,
    required this.transmitStatus,
    required this.openedAtIso,
    required this.openingCash,
    this.remoteId,
    this.closedAtIso,
    this.countedCash,
    this.closeMode,
    this.notes,
    this.openingCountedByUser = false,
  });

  static const statusOpen = 'OPEN';
  static const statusClosed = 'CLOSED';
  static const transmitSynced = 'synced';
  static const transmitPending = 'pending_transmit';
  static const transmitFailed = 'failed';

  final String localId;
  final String? remoteId;
  final String storeId;
  final String deviceId;
  final String status;
  final String transmitStatus;
  final String openedAtIso;
  final String? closedAtIso;
  final String openingCash;
  final String? countedCash;
  final String? closeMode;
  final String? notes;

  /// True si el cajero pasó por «Abrir caja» (incluye fondo 0 intencional).
  /// False = OPEN legado/zombie automático con `0.00`.
  final bool openingCountedByUser;

  bool get isOpen => status == statusOpen;
  bool get isClosed => status == statusClosed;
  bool get needsTransmit =>
      isClosed && transmitStatus == transmitPending;

  /// OPEN local aún no creada en el servidor (`POST /cash-sessions` pendiente).
  bool get needsOpenTransmit =>
      isOpen && (remoteId == null || remoteId!.trim().isEmpty);

  /// Puede entrar al POS: turno OPEN y apertura confirmada por el cajero.
  bool get allowsPosSales => isOpen && openingCountedByUser;

  static bool isZeroOpeningCash(String? raw) {
    final n = double.tryParse((raw ?? '').trim().replaceAll(',', '.'));
    return n == null || n == 0;
  }

  LocalCashSession copyWith({
    String? remoteId,
    String? status,
    String? transmitStatus,
    String? openedAtIso,
    String? closedAtIso,
    String? openingCash,
    String? countedCash,
    String? closeMode,
    String? notes,
    bool? openingCountedByUser,
    bool clearRemoteId = false,
  }) {
    return LocalCashSession(
      localId: localId,
      remoteId: clearRemoteId ? null : (remoteId ?? this.remoteId),
      storeId: storeId,
      deviceId: deviceId,
      status: status ?? this.status,
      transmitStatus: transmitStatus ?? this.transmitStatus,
      openedAtIso: openedAtIso ?? this.openedAtIso,
      closedAtIso: closedAtIso ?? this.closedAtIso,
      openingCash: openingCash ?? this.openingCash,
      countedCash: countedCash ?? this.countedCash,
      closeMode: closeMode ?? this.closeMode,
      notes: notes ?? this.notes,
      openingCountedByUser:
          openingCountedByUser ?? this.openingCountedByUser,
    );
  }

  Map<String, dynamic> toJson() => {
    'localId': localId,
    'remoteId': remoteId,
    'storeId': storeId,
    'deviceId': deviceId,
    'status': status,
    'transmitStatus': transmitStatus,
    'openedAtIso': openedAtIso,
    'closedAtIso': closedAtIso,
    'openingCash': openingCash,
    'countedCash': countedCash,
    'closeMode': closeMode,
    'notes': notes,
    'openingCountedByUser': openingCountedByUser,
  };

  static LocalCashSession? tryFromJson(Map<String, dynamic> json) {
    final localId = json['localId']?.toString().trim() ?? '';
    final storeId = json['storeId']?.toString().trim() ?? '';
    final deviceId = json['deviceId']?.toString().trim() ?? '';
    final status = json['status']?.toString().trim() ?? '';
    final transmit = json['transmitStatus']?.toString().trim() ?? '';
    final opened = json['openedAtIso']?.toString().trim() ?? '';
    final opening = json['openingCash']?.toString().trim() ?? '0.00';
    if (localId.isEmpty ||
        storeId.isEmpty ||
        deviceId.isEmpty ||
        status.isEmpty ||
        transmit.isEmpty ||
        opened.isEmpty) {
      return null;
    }
    final countedFlag = json['openingCountedByUser'];
    final countedByUser = countedFlag == true ||
        countedFlag?.toString().toLowerCase() == 'true';
    return LocalCashSession(
      localId: localId,
      remoteId: json['remoteId']?.toString(),
      storeId: storeId,
      deviceId: deviceId,
      status: status,
      transmitStatus: transmit,
      openedAtIso: opened,
      closedAtIso: json['closedAtIso']?.toString(),
      openingCash: opening.isEmpty ? '0.00' : opening,
      countedCash: json['countedCash']?.toString(),
      closeMode: json['closeMode']?.toString(),
      notes: json['notes']?.toString(),
      openingCountedByUser: countedByUser,
    );
  }
}

class PendingSaleCloseDeclaration {
  const PendingSaleCloseDeclaration({
    required this.saleId,
    required this.opId,
    required this.total,
    required this.createdAt,
  });

  final String saleId;
  final String opId;
  final String total;
  final String createdAt;

  Map<String, dynamic> toJson() => {
    'saleId': saleId,
    'opId': opId,
    'total': total,
    'createdAt': createdAt,
  };
}
