import 'purchase.dart';

/// Preview / resultado de anulación (`POST .../void-preview` y `.../void`).
/// Contrato: `docs/ANULACION_FACTURA_PROVEEDOR_PLAN.md` §5.
class PurchaseVoidLinePreview {
  const PurchaseVoidLinePreview({
    required this.productId,
    this.productName,
    required this.quantityPurchased,
    required this.quantityReversible,
    required this.quantitySkipped,
    this.skipReason,
    this.stockOnHand,
  });

  final String productId;
  final String? productName;
  final String quantityPurchased;
  final String quantityReversible;
  final String quantitySkipped;
  final String? skipReason;
  final String? stockOnHand;

  bool get hasSkipped {
    final v = double.tryParse(quantitySkipped) ?? 0;
    return v > 0.0000001;
  }

  static PurchaseVoidLinePreview? tryFromJson(Map<String, dynamic> json) {
    final productId = json['productId']?.toString().trim() ?? '';
    if (productId.isEmpty) return null;
    return PurchaseVoidLinePreview(
      productId: productId,
      productName: json['productName']?.toString(),
      quantityPurchased: json['quantityPurchased']?.toString() ?? '0',
      quantityReversible: json['quantityReversible']?.toString() ?? '0',
      quantitySkipped: json['quantitySkipped']?.toString() ?? '0',
      skipReason: json['skipReason']?.toString(),
      stockOnHand: json['stockOnHand']?.toString(),
    );
  }
}

class PurchaseVoidPaymentsPreview {
  const PurchaseVoidPaymentsPreview({
    this.amountPaidFunctional,
    this.policy,
    this.willReversePayments = false,
  });

  final String? amountPaidFunctional;
  final String? policy;
  final bool willReversePayments;

  static PurchaseVoidPaymentsPreview fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PurchaseVoidPaymentsPreview();
    }
    return PurchaseVoidPaymentsPreview(
      amountPaidFunctional: json['amountPaidFunctional']?.toString(),
      policy: json['policy']?.toString(),
      willReversePayments: json['willReversePayments'] == true,
    );
  }
}

class PurchaseVoidDebtPreview {
  const PurchaseVoidDebtPreview({
    this.amountDueFunctionalBefore,
    this.amountDueFunctionalAfter,
  });

  final String? amountDueFunctionalBefore;
  final String? amountDueFunctionalAfter;

  static PurchaseVoidDebtPreview fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const PurchaseVoidDebtPreview();
    }
    return PurchaseVoidDebtPreview(
      amountDueFunctionalBefore: json['amountDueFunctionalBefore']?.toString(),
      amountDueFunctionalAfter: json['amountDueFunctionalAfter']?.toString(),
    );
  }
}

class PurchaseVoidPreview {
  const PurchaseVoidPreview({
    required this.purchaseId,
    required this.canVoid,
    this.blockers = const [],
    this.lines = const [],
    this.payments = const PurchaseVoidPaymentsPreview(),
    this.debt = const PurchaseVoidDebtPreview(),
    this.warnings = const [],
    this.isMock = false,
    this.voidedAt,
  });

  final String purchaseId;
  final bool canVoid;
  final List<String> blockers;
  final List<PurchaseVoidLinePreview> lines;
  final PurchaseVoidPaymentsPreview payments;
  final PurchaseVoidDebtPreview debt;
  final List<String> warnings;

  /// true = generado en app; aún no vino del backend.
  final bool isMock;
  final String? voidedAt;

  bool get hasPartialStockSkip => lines.any((l) => l.hasSkipped);

  static PurchaseVoidPreview? tryFromJson(Map<String, dynamic> json) {
    final purchaseId = json['purchaseId']?.toString().trim() ?? '';
    if (purchaseId.isEmpty) return null;
    final linesRaw = json['lines'];
    final lines = <PurchaseVoidLinePreview>[];
    if (linesRaw is List) {
      for (final e in linesRaw) {
        if (e is Map) {
          final line = PurchaseVoidLinePreview.tryFromJson(
            Map<String, dynamic>.from(e),
          );
          if (line != null) lines.add(line);
        }
      }
    }
    final blockersRaw = json['blockers'];
    final blockers = <String>[];
    if (blockersRaw is List) {
      for (final e in blockersRaw) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) blockers.add(s);
      }
    }
    final warningsRaw = json['warnings'];
    final warnings = <String>[];
    if (warningsRaw is List) {
      for (final e in warningsRaw) {
        final s = e?.toString().trim();
        if (s != null && s.isNotEmpty) warnings.add(s);
      }
    }
    final paymentsJson = json['payments'];
    final debtJson = json['debt'];
    return PurchaseVoidPreview(
      purchaseId: purchaseId,
      canVoid: json['canVoid'] != false,
      blockers: blockers,
      lines: lines,
      payments: PurchaseVoidPaymentsPreview.fromJson(
        paymentsJson is Map ? Map<String, dynamic>.from(paymentsJson) : null,
      ),
      debt: PurchaseVoidDebtPreview.fromJson(
        debtJson is Map ? Map<String, dynamic>.from(debtJson) : null,
      ),
      warnings: warnings,
      isMock: json['isMock'] == true,
      voidedAt: json['voidedAt']?.toString(),
    );
  }
}

class PurchaseVoidRequest {
  const PurchaseVoidRequest({
    required this.opId,
    required this.reason,
    this.confirmPartialStock = false,
    this.mode = 'AUTO',
  });

  final String opId;
  final String reason;
  final bool confirmPartialStock;
  final String mode;

  Map<String, dynamic> toJson() => {
        'opId': opId,
        'reason': reason.trim(),
        'confirmPartialStock': confirmPartialStock,
        'mode': mode,
      };
}

/// Mock local para UI mientras el API void no está listo.
/// No consulta stock real: asume reversible = comprado (caso feliz) y avisa.
class PurchaseVoidMock {
  PurchaseVoidMock._();

  static PurchaseVoidPreview fromDetail(PurchaseDetail detail) {
    final lines = <PurchaseVoidLinePreview>[];
    for (final l in detail.lines) {
      lines.add(
        PurchaseVoidLinePreview(
          productId: l.productId,
          productName: l.productName,
          quantityPurchased: l.quantity,
          quantityReversible: l.quantity,
          quantitySkipped: '0',
          skipReason: null,
          stockOnHand: null,
        ),
      );
    }
    if (lines.isEmpty) {
      lines.add(
        const PurchaseVoidLinePreview(
          productId: '—',
          productName: '(Sin líneas en detalle)',
          quantityPurchased: '0',
          quantityReversible: '0',
          quantitySkipped: '0',
        ),
      );
    }
    final paid = detail.summary.amountPaidFunctional ?? '0';
    final due = detail.summary.amountDueFunctional ?? '0';
    final paidN = double.tryParse(paid) ?? 0;
    return PurchaseVoidPreview(
      purchaseId: detail.summary.id,
      canVoid: true,
      lines: lines,
      payments: PurchaseVoidPaymentsPreview(
        amountPaidFunctional: paid,
        policy: 'REVERSE_ON_VOID',
        willReversePayments: paidN > 0.0000001,
      ),
      debt: PurchaseVoidDebtPreview(
        amountDueFunctionalBefore: due,
        amountDueFunctionalAfter: '0',
      ),
      warnings: const [
        'Vista previa MOCK — el backend aún no calcula stock real ni ventas.',
        'Cuando exista el API, aquí se verá cuánto no se puede revertir '
            '(mercancía ya vendida).',
      ],
      isMock: true,
    );
  }
}
