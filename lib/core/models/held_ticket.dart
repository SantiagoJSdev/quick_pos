import '../pos/money_string_math.dart';
import 'pos_cart_line.dart';

/// Borrador local ON_HOLD — **no** es venta ni operación de sync (ver `POS_TICKETS_EN_ESPERA_FRONT_BACKEND.md`).
class HeldTicketLine {
  const HeldTicketLine({
    required this.productId,
    required this.nameSnapshot,
    required this.quantity,
    required this.price,
    required this.currency,
    required this.catalogUnitPrice,
    required this.catalogCurrency,
    this.discount = '0',
    this.isByWeight = false,
    this.displayGrams,
    this.pricePerKgFunctional,
    this.lineAmountFunctional,
    this.lineAmountDocument,
  });

  final String productId;
  final String nameSnapshot;
  final String quantity;

  /// Precio unitario en moneda documento (como en `POST /sales`).
  final String price;
  final String currency;
  final String catalogUnitPrice;
  final String catalogCurrency;
  final String discount;
  final bool isByWeight;
  final String? displayGrams;
  final String? pricePerKgFunctional;
  final String? lineAmountFunctional;
  final String? lineAmountDocument;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'name': nameSnapshot,
    'quantity': quantity,
    'price': price,
    'currency': currency,
    'catalogUnitPrice': catalogUnitPrice,
    'catalogCurrency': catalogCurrency,
    'discount': discount,
    'isByWeight': isByWeight,
    'displayGrams': displayGrams,
    'pricePerKgFunctional': pricePerKgFunctional,
    'lineAmountFunctional': lineAmountFunctional,
    'lineAmountDocument': lineAmountDocument,
  };

  static HeldTicketLine? tryFromJson(Map<String, dynamic> json) {
    final pid = json['productId']?.toString().trim();
    if (pid == null || pid.isEmpty) return null;
    final qty = json['quantity']?.toString().trim() ?? '1';
    final price = json['price']?.toString().trim() ?? '';
    if (price.isEmpty) return null;
    final cur = json['currency']?.toString().trim() ?? '';
    if (cur.isEmpty) return null;
    return HeldTicketLine(
      productId: pid,
      nameSnapshot: json['name']?.toString() ?? '',
      quantity: qty,
      price: price,
      currency: cur,
      catalogUnitPrice: json['catalogUnitPrice']?.toString().trim() ?? price,
      catalogCurrency:
          json['catalogCurrency']?.toString().trim().isNotEmpty == true
          ? json['catalogCurrency'].toString().trim()
          : cur,
      discount: json['discount']?.toString().trim() ?? '0',
      isByWeight: json['isByWeight'] == true,
      displayGrams: json['displayGrams']?.toString(),
      pricePerKgFunctional: json['pricePerKgFunctional']?.toString(),
      lineAmountFunctional: json['lineAmountFunctional']?.toString(),
      lineAmountDocument: json['lineAmountDocument']?.toString(),
    );
  }

  PosCartLine toPosCartLine() {
    return PosCartLine(
      productId: productId,
      name: nameSnapshot.isNotEmpty ? nameSnapshot : 'Producto',
      sku: '',
      catalogUnitPrice: catalogUnitPrice,
      catalogCurrency: catalogCurrency,
      documentUnitPrice: price,
      documentCurrencyCode: currency,
      quantity: quantity,
      isByWeight: isByWeight,
      displayGrams: displayGrams,
      pricePerKgFunctional: pricePerKgFunctional,
      lineAmountFunctional: lineAmountFunctional,
      lineAmountDocument: lineAmountDocument,
    );
  }
}

class HeldTicket {
  const HeldTicket({
    required this.id,
    required this.storeId,
    required this.deviceId,
    required this.status,
    required this.documentCurrencyCode,
    required this.fxSnapshot,
    required this.totals,
    required this.lines,
    required this.createdAtIso,
    required this.updatedAtIso,
    this.alias,
    this.note,
    this.heldByUserId,
  });

  final String id;
  final String storeId;
  final String deviceId;
  final String status;
  final String? alias;
  final String? note;
  final String documentCurrencyCode;
  final Map<String, dynamic> fxSnapshot;
  final Map<String, dynamic> totals;
  final List<HeldTicketLine> lines;
  final String createdAtIso;
  final String updatedAtIso;
  final String? heldByUserId;

  static const statusOnHold = 'ON_HOLD';

  String get displayTitle {
    final a = alias?.trim();
    if (a != null && a.isNotEmpty) return a;
    return 'Ticket ${id.substring(0, 8)}';
  }

  String get subtotalDocument =>
      totals['subtotal']?.toString() ?? totals['total']?.toString() ?? '0';
  String get totalDocument => totals['total']?.toString() ?? '0';
  String get totalFunctional => totals['totalFunctional']?.toString() ?? '—';

  int get lineCount => lines.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'storeId': storeId,
    'deviceId': deviceId,
    'status': status,
    'alias': alias,
    'note': note,
    'documentCurrencyCode': documentCurrencyCode,
    'fxSnapshot': fxSnapshot,
    'totals': totals,
    'lines': lines.map((e) => e.toJson()).toList(),
    'createdAt': createdAtIso,
    'updatedAt': updatedAtIso,
    'heldByUserId': heldByUserId,
  };

  static HeldTicket? tryFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim();
    final storeId = json['storeId']?.toString().trim();
    final deviceId = json['deviceId']?.toString().trim();
    if (id == null ||
        id.isEmpty ||
        storeId == null ||
        storeId.isEmpty ||
        deviceId == null ||
        deviceId.isEmpty) {
      return null;
    }
    final doc = json['documentCurrencyCode']?.toString().trim();
    if (doc == null || doc.isEmpty) return null;
    final fxRaw = json['fxSnapshot'];
    if (fxRaw is! Map) return null;
    final totRaw = json['totals'];
    if (totRaw is! Map) return null;
    final linesRaw = json['lines'];
    if (linesRaw is! List) return null;
    final lines = <HeldTicketLine>[];
    for (final e in linesRaw) {
      if (e is! Map) continue;
      final l = HeldTicketLine.tryFromJson(Map<String, dynamic>.from(e));
      if (l != null) lines.add(l);
    }
    if (lines.isEmpty) return null;
    return HeldTicket(
      id: id,
      storeId: storeId,
      deviceId: deviceId,
      status: json['status']?.toString() ?? statusOnHold,
      alias: json['alias']?.toString(),
      note: json['note']?.toString(),
      documentCurrencyCode: doc,
      fxSnapshot: Map<String, dynamic>.from(fxRaw),
      totals: Map<String, dynamic>.from(totRaw),
      lines: lines,
      createdAtIso: json['createdAt']?.toString() ?? '',
      updatedAtIso: json['updatedAt']?.toString() ?? '',
      heldByUserId: json['heldByUserId']?.toString(),
    );
  }

  /// Construye un ticket en espera desde el carrito actual (snapshot).
  static HeldTicket fromPosCart({
    required String id,
    required String storeId,
    required String deviceId,
    required String documentCurrencyCode,
    required Map<String, dynamic> fxSnapshot,
    required List<PosCartLine> cartLines,
    String? alias,
    String? note,
    String? totalFunctional,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    final lines = cartLines
        .map(
          (l) => HeldTicketLine(
            productId: l.productId,
            nameSnapshot: l.name,
            quantity: l.quantity,
            price: l.documentUnitPrice,
            currency: l.documentCurrencyCode,
            catalogUnitPrice: l.catalogUnitPrice,
            catalogCurrency: l.catalogCurrency,
            isByWeight: l.isByWeight,
            displayGrams: l.displayGrams,
            pricePerKgFunctional: l.pricePerKgFunctional,
            lineAmountFunctional: l.lineAmountFunctional,
            lineAmountDocument: l.lineAmountDocument,
          ),
        )
        .toList();
    final subtotal = MoneyStringMath.sum(
      lines.map((l) => MoneyStringMath.multiply(l.price, l.quantity)),
    );
    final totals = <String, dynamic>{
      'subtotal': subtotal,
      'discount': '0',
      'total': subtotal,
      if (totalFunctional != null && totalFunctional.isNotEmpty)
        'totalFunctional': totalFunctional,
    };
    return HeldTicket(
      id: id,
      storeId: storeId,
      deviceId: deviceId,
      status: statusOnHold,
      alias: alias,
      note: note,
      documentCurrencyCode: documentCurrencyCode,
      fxSnapshot: fxSnapshot,
      totals: totals,
      lines: lines,
      createdAtIso: now,
      updatedAtIso: now,
    );
  }
}
