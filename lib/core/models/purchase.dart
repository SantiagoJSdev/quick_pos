/// Modelos de `GET/POST /purchases` y payables (montos como string).
class PurchaseSummary {
  const PurchaseSummary({
    required this.id,
    required this.supplierId,
    this.supplierName,
    this.supplierInvoiceReference,
    this.paymentStatus,
    this.documentCurrencyCode,
    this.totalDocument,
    this.totalFunctional,
    this.amountPaidFunctional,
    this.amountDueFunctional,
    this.dueDate,
    this.paidAt,
    this.createdAt,
  });

  final String id;
  final String supplierId;
  final String? supplierName;
  final String? supplierInvoiceReference;
  final String? paymentStatus;
  final String? documentCurrencyCode;
  final String? totalDocument;
  final String? totalFunctional;
  final String? amountPaidFunctional;
  final String? amountDueFunctional;
  final String? dueDate;
  final String? paidAt;
  final String? createdAt;

  bool get isOpen {
    final s = (paymentStatus ?? '').toUpperCase();
    if (s == 'CREDIT' || s == 'PARTIAL') return true;
    final due = double.tryParse(amountDueFunctional ?? '') ?? 0;
    return due > 0.0000001;
  }

  static PurchaseSummary? tryFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    final supplierId = _supplierIdFrom(json);
    return PurchaseSummary(
      id: id,
      supplierId: supplierId,
      supplierName: _supplierNameFrom(json),
      supplierInvoiceReference:
          json['supplierInvoiceReference']?.toString() ??
          json['reference']?.toString(),
      paymentStatus: json['paymentStatus']?.toString(),
      documentCurrencyCode: json['documentCurrencyCode']?.toString(),
      totalDocument: _money(json['totalDocument'] ?? json['total']),
      totalFunctional: _money(json['totalFunctional']),
      amountPaidFunctional: _money(json['amountPaidFunctional']),
      amountDueFunctional: _money(json['amountDueFunctional']),
      dueDate: json['dueDate']?.toString(),
      paidAt: json['paidAt']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }

  static String _supplierIdFrom(Map<String, dynamic> json) {
    final direct = json['supplierId']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = json['supplier'];
    if (nested is Map) {
      return nested['id']?.toString().trim() ?? '';
    }
    return '';
  }

  static String? _supplierNameFrom(Map<String, dynamic> json) {
    final nested = json['supplier'];
    if (nested is Map) {
      final n = nested['name']?.toString().trim();
      if (n != null && n.isNotEmpty) return n;
    }
    final n = json['supplierName']?.toString().trim();
    return (n == null || n.isEmpty) ? null : n;
  }

  static String? _money(Object? v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}

class PurchaseLine {
  const PurchaseLine({
    required this.productId,
    this.productName,
    required this.quantity,
    required this.unitCost,
  });

  final String productId;
  final String? productName;
  final String quantity;
  final String unitCost;

  static PurchaseLine? tryFromJson(Map<String, dynamic> json) {
    final productId = json['productId']?.toString().trim() ?? '';
    if (productId.isEmpty) {
      final nested = json['product'];
      if (nested is Map) {
        final id = nested['id']?.toString().trim() ?? '';
        if (id.isEmpty) return null;
        return PurchaseLine(
          productId: id,
          productName: nested['name']?.toString(),
          quantity: json['quantity']?.toString() ?? '',
          unitCost: json['unitCost']?.toString() ?? '',
        );
      }
      return null;
    }
    String? name = json['productName']?.toString();
    final nested = json['product'];
    if (nested is Map) {
      name ??= nested['name']?.toString();
    }
    return PurchaseLine(
      productId: productId,
      productName: name,
      quantity: json['quantity']?.toString() ?? '',
      unitCost: json['unitCost']?.toString() ?? '',
    );
  }
}

class PurchasePayment {
  const PurchasePayment({
    required this.id,
    required this.amountFunctional,
    this.method,
    this.createdAt,
  });

  final String id;
  final String amountFunctional;
  final String? method;
  final String? createdAt;

  static PurchasePayment? tryFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final amount =
        json['amountFunctional']?.toString() ?? json['amount']?.toString();
    if (id.isEmpty || amount == null || amount.trim().isEmpty) return null;
    return PurchasePayment(
      id: id,
      amountFunctional: amount.trim(),
      method: json['method']?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}

class PurchaseDetail {
  const PurchaseDetail({
    required this.summary,
    this.lines = const [],
    this.payments = const [],
  });

  final PurchaseSummary summary;
  final List<PurchaseLine> lines;
  final List<PurchasePayment> payments;

  static PurchaseDetail? tryFromJson(Map<String, dynamic> json) {
    final summary = PurchaseSummary.tryFromJson(json);
    if (summary == null) return null;
    final linesRaw = json['lines'];
    final lines = <PurchaseLine>[];
    if (linesRaw is List) {
      for (final e in linesRaw) {
        if (e is Map) {
          final line = PurchaseLine.tryFromJson(Map<String, dynamic>.from(e));
          if (line != null) lines.add(line);
        }
      }
    }
    final payRaw = json['payments'];
    final payments = <PurchasePayment>[];
    if (payRaw is List) {
      for (final e in payRaw) {
        if (e is Map) {
          final p = PurchasePayment.tryFromJson(Map<String, dynamic>.from(e));
          if (p != null) payments.add(p);
        }
      }
    }
    return PurchaseDetail(
      summary: summary,
      lines: lines,
      payments: payments,
    );
  }
}

class PurchaseListPage {
  const PurchaseListPage({required this.items, this.nextCursor});

  final List<PurchaseSummary> items;
  final String? nextCursor;

  static PurchaseListPage fromJson(Map<String, dynamic> json) {
    final items = <PurchaseSummary>[];
    final raw = json['items'] ?? json['data'] ?? json['results'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final p = PurchaseSummary.tryFromJson(Map<String, dynamic>.from(e));
          if (p != null) items.add(p);
        }
      }
    }
    final cursor = json['nextCursor']?.toString();
    return PurchaseListPage(
      items: items,
      nextCursor: (cursor == null || cursor.isEmpty) ? null : cursor,
    );
  }

  /// Si la API responde array plano.
  static PurchaseListPage fromList(List<Map<String, dynamic>> list) {
    final items = <PurchaseSummary>[];
    for (final e in list) {
      final p = PurchaseSummary.tryFromJson(e);
      if (p != null) items.add(p);
    }
    return PurchaseListPage(items: items);
  }
}

/// Fila de `GET /purchases/payables`.
class PayableRow {
  const PayableRow({
    required this.supplierId,
    required this.supplierName,
    required this.amountDueFunctional,
    this.openPurchasesCount,
  });

  final String supplierId;
  final String supplierName;
  final String amountDueFunctional;
  final int? openPurchasesCount;

  static PayableRow? tryFromJson(Map<String, dynamic> json) {
    final supplierId =
        json['supplierId']?.toString().trim() ??
        (json['supplier'] is Map
            ? (json['supplier'] as Map)['id']?.toString().trim()
            : null) ??
        '';
    if (supplierId.isEmpty) return null;
    String name =
        json['supplierName']?.toString().trim() ??
        (json['supplier'] is Map
            ? (json['supplier'] as Map)['name']?.toString().trim()
            : null) ??
        '';
    if (name.isEmpty) name = 'Proveedor';
    final due =
        json['amountDueFunctional']?.toString() ??
        json['totalDueFunctional']?.toString() ??
        json['due']?.toString() ??
        '0';
    int? count;
    final c = json['openPurchasesCount'] ?? json['purchaseCount'] ?? json['count'];
    if (c is int) {
      count = c;
    } else if (c is String) {
      count = int.tryParse(c);
    }
    return PayableRow(
      supplierId: supplierId,
      supplierName: name,
      amountDueFunctional: due.trim(),
      openPurchasesCount: count,
    );
  }
}
