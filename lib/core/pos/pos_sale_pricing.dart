import 'money_string_math.dart';
import 'sale_checkout_payload.dart';

/// Precio de catálogo → unidad en **moneda documento** (solo funcional o ya documento).
class PosSalePricing {
  PosSalePricing._();

  static String? documentUnitPrice({
    required String catalogPrice,
    required String catalogCurrency,
    required String documentCurrencyCode,
    required String functionalCurrencyCode,
    required SaleFxPair? pair,
  }) {
    final doc = documentCurrencyCode.toUpperCase();
    final func = functionalCurrencyCode.toUpperCase();
    final pc = catalogCurrency.toUpperCase();
    if (pc == doc) return catalogPrice.trim();
    if (pc != func) return null;
    if (func == doc) return catalogPrice.trim();
    if (pair == null) return null;
    final r = pair.rate;
    if (!pair.inverted) {
      return MoneyStringMath.multiply(catalogPrice, r.rateQuotePerBase);
    }
    return MoneyStringMath.divide(catalogPrice, r.rateQuotePerBase, fractionDigits: 2);
  }
}
