/// Reglas UI para `IN_ADJUST` — contrato backend (stock ≤ 0 + Product.cost).
class InAdjustUnitCostPolicy {
  const InAdjustUnitCostPolicy({
    required this.currentStockQuantity,
    this.catalogUnitCost,
  });

  final double currentStockQuantity;
  final String? catalogUnitCost;

  static double? parsePositiveAmount(String? raw) {
    final t = raw?.trim().replaceAll(',', '.');
    if (t == null || t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null || v.isNaN || v <= 0) return null;
    return v;
  }

  bool get isZeroOrNegativeStock => currentStockQuantity <= 0;

  bool get catalogHasPositiveCost =>
      parsePositiveAmount(catalogUnitCost) != null;

  /// Entrada con stock ≤ 0 y sin costo en catálogo → campo obligatorio.
  bool get unitCostRequired =>
      isZeroOrNegativeStock && !catalogHasPositiveCost;

  String? validateExplicitUnitCost(String? raw) {
    final t = raw?.trim();
    if (t == null || t.isEmpty) return null;
    if (parsePositiveAmount(t) == null) {
      return 'Costo unitario (func.): número mayor que 0.';
    }
    return null;
  }

  String? validateForSubmit({
    required String adjustType,
    required String unitCostRaw,
  }) {
    if (adjustType != 'IN_ADJUST') return null;
    final cost = unitCostRaw.trim();
    final explicitError = validateExplicitUnitCost(cost);
    if (explicitError != null) return explicitError;
    if (unitCostRequired && cost.isEmpty) {
      return 'Con stock en cero, indicá el costo unitario (funcional) '
          'o cargá costo en la ficha del producto.';
    }
    return null;
  }
}
