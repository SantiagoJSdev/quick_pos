/// Entrada del historial local de tickets (venta confirmada o en cola offline).
class RecentSaleTicket {
  const RecentSaleTicket({
    required this.storeId,
    required this.saleId,
    required this.totalDocument,
    required this.documentCurrencyCode,
    required this.recordedAtIso,
    required this.status,
  });

  static const statusSynced = 'synced';
  static const statusQueued = 'queued';

  final String storeId;
  final String saleId;
  final String totalDocument;
  final String documentCurrencyCode;
  final String recordedAtIso;

  /// [statusSynced] = respuesta `POST /sales`; [statusQueued] = cola offline.
  final String status;

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'saleId': saleId,
        'totalDocument': totalDocument,
        'documentCurrencyCode': documentCurrencyCode,
        'recordedAtIso': recordedAtIso,
        'status': status,
      };

  static RecentSaleTicket? tryFromJson(Map<String, dynamic> json) {
    final storeId = json['storeId'] as String?;
    final saleId = json['saleId'] as String?;
    final total = json['totalDocument'] as String?;
    final doc = json['documentCurrencyCode'] as String?;
    final at = json['recordedAtIso'] as String?;
    final st = json['status'] as String?;
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
    );
  }

  /// Política app: historial **local** solo conserva ventas del **día calendario actual**
  /// en la zona horaria local del dispositivo (`recordedAtIso` en ISO-8601).
  bool get isRecordedOnLocalCalendarToday {
    final dt = DateTime.tryParse(recordedAtIso);
    if (dt == null) return false;
    final local = dt.toLocal();
    final now = DateTime.now();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }
}
