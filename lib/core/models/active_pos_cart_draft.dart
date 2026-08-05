import 'pos_cart_line.dart';

/// Borrador del ticket actual en POS (persistencia local).
/// No es venta ni sync: solo evita perder líneas al salir de la pantalla / app.
class ActivePosCartDraft {
  const ActivePosCartDraft({
    required this.storeId,
    required this.deviceId,
    required this.documentCurrencyCode,
    required this.lines,
    required this.updatedAtIso,
    this.activeHeldTicketId,
  });

  final String storeId;
  final String deviceId;
  final String documentCurrencyCode;
  final List<PosCartLine> lines;
  final String updatedAtIso;
  final String? activeHeldTicketId;

  Map<String, dynamic> toJson() => {
    'storeId': storeId,
    'deviceId': deviceId,
    'documentCurrencyCode': documentCurrencyCode,
    'updatedAtIso': updatedAtIso,
    'activeHeldTicketId': activeHeldTicketId,
    'lines': lines.map(_lineToJson).toList(),
  };

  static Map<String, dynamic> _lineToJson(PosCartLine l) => {
    'productId': l.productId,
    'name': l.name,
    'sku': l.sku,
    'catalogUnitPrice': l.catalogUnitPrice,
    'catalogCurrency': l.catalogCurrency,
    'documentUnitPrice': l.documentUnitPrice,
    'documentCurrencyCode': l.documentCurrencyCode,
    'quantity': l.quantity,
    'isByWeight': l.isByWeight,
    'displayGrams': l.displayGrams,
    'pricePerKgFunctional': l.pricePerKgFunctional,
    'lineAmountFunctional': l.lineAmountFunctional,
    'lineAmountDocument': l.lineAmountDocument,
    'isCashAdvance': l.isCashAdvance,
    'advanceBaseDocument': l.advanceBaseDocument,
  };

  static PosCartLine? _lineFromJson(Map<String, dynamic> json) {
    final pid = json['productId']?.toString().trim();
    if (pid == null || pid.isEmpty) return null;
    final price = json['documentUnitPrice']?.toString().trim() ?? '';
    final cur = json['documentCurrencyCode']?.toString().trim() ?? '';
    if (price.isEmpty || cur.isEmpty) return null;
    return PosCartLine(
      productId: pid,
      name: json['name']?.toString() ?? 'Producto',
      sku: json['sku']?.toString() ?? '',
      catalogUnitPrice:
          json['catalogUnitPrice']?.toString().trim().isNotEmpty == true
          ? json['catalogUnitPrice'].toString().trim()
          : price,
      catalogCurrency:
          json['catalogCurrency']?.toString().trim().isNotEmpty == true
          ? json['catalogCurrency'].toString().trim()
          : cur,
      documentUnitPrice: price,
      documentCurrencyCode: cur,
      quantity: json['quantity']?.toString().trim() ?? '1',
      isByWeight: json['isByWeight'] == true,
      displayGrams: json['displayGrams']?.toString(),
      pricePerKgFunctional: json['pricePerKgFunctional']?.toString(),
      lineAmountFunctional: json['lineAmountFunctional']?.toString(),
      lineAmountDocument: json['lineAmountDocument']?.toString(),
      isCashAdvance: json['isCashAdvance'] == true,
      advanceBaseDocument: json['advanceBaseDocument']?.toString(),
    );
  }

  static ActivePosCartDraft? tryFromJson(Map<String, dynamic> json) {
    final storeId = json['storeId']?.toString().trim() ?? '';
    final deviceId = json['deviceId']?.toString().trim() ?? '';
    final doc = json['documentCurrencyCode']?.toString().trim() ?? '';
    if (storeId.isEmpty || deviceId.isEmpty || doc.isEmpty) return null;
    final rawLines = json['lines'];
    if (rawLines is! List || rawLines.isEmpty) return null;
    final lines = <PosCartLine>[];
    for (final e in rawLines) {
      if (e is! Map) continue;
      final l = _lineFromJson(Map<String, dynamic>.from(e));
      if (l != null) lines.add(l);
    }
    if (lines.isEmpty) return null;
    return ActivePosCartDraft(
      storeId: storeId,
      deviceId: deviceId,
      documentCurrencyCode: doc,
      lines: lines,
      updatedAtIso: json['updatedAtIso']?.toString() ?? '',
      activeHeldTicketId: json['activeHeldTicketId']?.toString(),
    );
  }
}
