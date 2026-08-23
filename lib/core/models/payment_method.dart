/// Ítem de `GET /api/v1/payment-methods` — `docs/KPI_CONTRATO_FRONT.md` §6.
class PaymentMethod {
  const PaymentMethod({
    required this.id,
    required this.code,
    required this.name,
    this.commissionPercent = '0',
    this.isCashLike = false,
    this.active = true,
  });

  final String id;
  final String code;
  final String name;
  final String commissionPercent;
  final bool isCashLike;
  final bool active;

  double get commissionPercentValue {
    final v = double.tryParse(commissionPercent.trim().replaceAll(',', '.'));
    return v == null || v.isNaN ? 0 : v;
  }

  bool get hasCommissionWarning => commissionPercentValue > 0;

  static PaymentMethod? tryFromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    final code = json['code']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (code.isEmpty) return null;
    return PaymentMethod(
      id: id,
      code: code,
      name: name.isEmpty ? code : name,
      commissionPercent: json['commissionPercent']?.toString() ?? '0',
      isCashLike: json['isCashLike'] == true,
      active: json['active'] != false,
    );
  }

  /// Offline / sin catálogo: efectivo funcional mínimo.
  static PaymentMethod fallbackCash(String functionalCode) {
    final c = functionalCode.trim().toUpperCase();
    return PaymentMethod(
      id: '',
      code: 'CASH_$c',
      name: 'Efectivo $c',
      commissionPercent: '0',
      isCashLike: true,
      active: true,
    );
  }
}

/// Línea de pago aplicada en el POS antes de cobrar.
class PosAppliedPayment {
  const PosAppliedPayment({
    required this.methodCode,
    required this.methodName,
    required this.amountFunctional,
    this.commissionPercent,
  });

  final String methodCode;
  final String methodName;
  final double amountFunctional;
  final String? commissionPercent;
}
