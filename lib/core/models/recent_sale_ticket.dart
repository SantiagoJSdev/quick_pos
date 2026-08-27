/// Entrada del historial local de tickets (venta confirmada o en cola offline).
class RecentSaleTicket {
  const RecentSaleTicket({
    required this.storeId,
    required this.saleId,
    required this.totalDocument,
    required this.documentCurrencyCode,
    required this.recordedAtIso,
    required this.status,
    this.displayCode,
    this.totalFunctional,
    this.functionalCurrencyCode,
  });

  static const statusSynced = 'synced';
  static const statusQueued = 'queued';
  /// Devolución/anulación registrada (no suma en cierre local).
  static const statusReturned = 'returned';

  final String storeId;
  final String saleId;
  final String totalDocument;
  final String documentCurrencyCode;
  final String recordedAtIso;

  /// [statusSynced] = en servidor; [statusQueued] = cola; [statusReturned] = anulada/devuelta.
  final String status;

  /// Número corto del día (ej. `00042`) para copiar / devoluciones; opcional en datos viejos.
  final String? displayCode;

  /// Total en moneda funcional (p. ej. USD). Opcional en tickets viejos.
  final String? totalFunctional;

  /// Código de moneda funcional (p. ej. `USD`).
  final String? functionalCurrencyCode;

  Map<String, dynamic> toJson() => {
    'storeId': storeId,
    'saleId': saleId,
    'totalDocument': totalDocument,
    'documentCurrencyCode': documentCurrencyCode,
    'recordedAtIso': recordedAtIso,
    'status': status,
    if (displayCode != null && displayCode!.isNotEmpty)
      'displayCode': displayCode,
    if (totalFunctional != null && totalFunctional!.isNotEmpty)
      'totalFunctional': totalFunctional,
    if (functionalCurrencyCode != null &&
        functionalCurrencyCode!.isNotEmpty)
      'functionalCurrencyCode': functionalCurrencyCode,
  };

  static RecentSaleTicket? tryFromJson(Map<String, dynamic> json) {
    final storeId = json['storeId'] as String?;
    final saleId = json['saleId'] as String?;
    final total = json['totalDocument'] as String?;
    final doc = json['documentCurrencyCode'] as String?;
    final at = json['recordedAtIso'] as String?;
    final st = json['status'] as String?;
    final dc = json['displayCode'] as String?;
    final tf = json['totalFunctional'] as String?;
    final fc = json['functionalCurrencyCode'] as String?;
    if (storeId == null ||
        storeId.isEmpty ||
        saleId == null ||
        saleId.isEmpty ||
        total == null ||
        doc == null ||
        at == null ||
        st == null) {
      return null;
    }
    return RecentSaleTicket(
      storeId: storeId,
      saleId: saleId,
      totalDocument: total,
      documentCurrencyCode: doc,
      recordedAtIso: at,
      status: st,
      displayCode: (dc != null && dc.isNotEmpty) ? dc : null,
      totalFunctional: (tf != null && tf.isNotEmpty) ? tf : null,
      functionalCurrencyCode: (fc != null && fc.isNotEmpty) ? fc : null,
    );
  }

  RecentSaleTicket copyWith({
    String? status,
    String? saleId,
    String? displayCode,
    String? totalFunctional,
    String? functionalCurrencyCode,
  }) {
    return RecentSaleTicket(
      storeId: storeId,
      saleId: saleId ?? this.saleId,
      totalDocument: totalDocument,
      documentCurrencyCode: documentCurrencyCode,
      recordedAtIso: recordedAtIso,
      status: status ?? this.status,
      displayCode: displayCode ?? this.displayCode,
      totalFunctional: totalFunctional ?? this.totalFunctional,
      functionalCurrencyCode:
          functionalCurrencyCode ?? this.functionalCurrencyCode,
    );
  }

  /// Texto principal para lista/detalle: prioriza funcional (USD).
  String get primaryTotalLabel {
    final tf = totalFunctional?.trim();
    if (tf != null && tf.isNotEmpty) {
      final c = (functionalCurrencyCode ?? 'USD').trim();
      return c.isEmpty ? tf : '$tf $c';
    }
    final c = documentCurrencyCode.trim();
    return c.isEmpty ? totalDocument : '$totalDocument $c';
  }

  /// Compara códigos con o sin ceros a la izquierda (ej. `42` == `00042`).
  static bool displayCodeMatches(String? stored, String userInput) {
    final a = int.tryParse((stored ?? '').trim());
    final b = int.tryParse(userInput.trim());
    if (a == null || b == null) return false;
    return a == b;
  }

  /// Política app: historial **local** solo conserva ventas del **día calendario actual**
  /// en la zona horaria local del dispositivo (`recordedAtIso` en ISO-8601).
  bool get isRecordedOnLocalCalendarToday {
    final dt = DateTime.tryParse(recordedAtIso);
    if (dt == null) return false;
    final local = dt.isUtc ? dt.toLocal() : dt;
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  /// **Hoy o ayer** (calendario local del dispositivo). Evita perder la venta de “esta mañana”
  /// si el día ya cambió o hubo desfase con el servidor.
  bool get isRecordedOnLocalDeviceHistoryWindow {
    final dt = DateTime.tryParse(recordedAtIso);
    if (dt == null) return false;
    final local = dt.isUtc ? dt.toLocal() : dt;
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(local.year, local.month, local.day);
    return d == today || d == yesterday;
  }
}
