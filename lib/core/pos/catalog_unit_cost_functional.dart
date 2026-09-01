import 'money_string_math.dart';
import 'sale_checkout_payload.dart';

/// `Product.cost` del catálogo local → **moneda funcional** (USD) al cobrar.
///
/// Misma convención FX que [PosSalePricing]: costo en moneda del producto.
String? catalogUnitCostFunctional({
  required String catalogCost,
  required String catalogCurrency,
  required String functionalCurrencyCode,
  required String documentCurrencyCode,
  required SaleFxPair? pair,
}) {
  final cost = catalogCost.trim().replaceAll(',', '.');
  if (cost.isEmpty) return '0.00';
  final parsed = double.tryParse(cost);
  if (parsed == null || parsed.isNaN) return '0.00';
  if (parsed == 0) return '0.00';

  final func = functionalCurrencyCode.trim().toUpperCase();
  final doc = documentCurrencyCode.trim().toUpperCase();
  final pc = catalogCurrency.trim().toUpperCase();
  if (pc.isEmpty) return null;

  if (pc == func) {
    return MoneyStringMath.divide(cost, '1', fractionDigits: 6);
  }
  if (pc == doc) {
    if (func == doc) return MoneyStringMath.divide(cost, '1', fractionDigits: 6);
    if (pair == null) return null;
    final rate = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: functionalCurrencyCode,
      documentCode: documentCurrencyCode,
      pair: pair,
    );
    return MoneyStringMath.divide(cost, rate, fractionDigits: 6);
  }
  return null;
}
