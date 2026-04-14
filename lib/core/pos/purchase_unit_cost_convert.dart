import 'money_string_math.dart';
import 'sale_checkout_payload.dart';

/// Costo unitario de la compra en [documentCurrencyCode]; [Product.cost] en
/// [productCurrencyCode]. Usa el mismo par funcional↔documento que la recepción.
/// `null` si la moneda del producto no es la del documento ni la funcional.
String? purchaseUnitCostInProductCurrency({
  required String unitCostDocument,
  required String documentCurrencyCode,
  required String functionalCurrencyCode,
  required SaleFxPair? fxPair,
  required String productCurrencyCode,
}) {
  final u = unitCostDocument.trim();
  if (u.isEmpty) return null;
  final doc = documentCurrencyCode.trim().toUpperCase();
  final func = functionalCurrencyCode.trim().toUpperCase();
  final pc = productCurrencyCode.trim().toUpperCase();
  if (pc.isEmpty) return null;

  if (pc == doc) {
    return MoneyStringMath.divide(u, '1', fractionDigits: 6);
  }
  if (pc == func) {
    if (doc == func) {
      return MoneyStringMath.divide(u, '1', fractionDigits: 6);
    }
    if (fxPair == null) return null;
    final rate = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: functionalCurrencyCode,
      documentCode: documentCurrencyCode,
      pair: fxPair,
    );
    return MoneyStringMath.divide(u, rate, fractionDigits: 6);
  }
  return null;
}
