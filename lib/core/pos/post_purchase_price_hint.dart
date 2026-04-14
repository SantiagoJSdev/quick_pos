import '../models/catalog_product.dart';
import 'money_string_math.dart';

/// P6 — política tras `POST /purchases`: el servidor **no** cambia `Product.price` solo.
/// Ver `docs/BACKEND_POST_PURCHASE_PRICE_POLICY.md`.
class PostPurchasePriceHint {
  PostPurchasePriceHint._();

  /// % para sugerencia sobre **costo medio de inventario**: margen propio del producto,
  /// margen de tienda si aplica `USE_STORE_DEFAULT`, o `null` en `MANUAL_PRICE` / sin dato.
  static String? marginPercentForAverageCostSuggestion({
    required CatalogProduct? product,
    String? storeDefaultMarginPercent,
  }) {
    if (product == null) return _trimOrNull(storeDefaultMarginPercent);
    final pm = product.pricingMode?.trim() ?? '';
    if (pm == 'MANUAL_PRICE') return null;
    if (pm == 'USE_PRODUCT_OVERRIDE') {
      return _trimOrNull(product.marginPercentOverride);
    }
    return _trimOrNull(storeDefaultMarginPercent);
  }

  static String? _trimOrNull(String? s) {
    final t = s?.trim();
    if (t == null || t.isEmpty) return null;
    return t;
  }

  static String pricingModeLabelEs(String? mode) {
    switch (mode?.trim() ?? '') {
      case 'USE_PRODUCT_OVERRIDE':
        return 'Margen propio (%)';
      case 'MANUAL_PRICE':
        return 'Precio manual';
      default:
        return 'Margen de la tienda';
    }
  }

  /// Precio sugerido = costo medio funcional × (1 + margenTienda/100). Solo UI; no sustituye `GET /products` (usa `Product.cost`).
  static String? suggestedListFromAverageCostAndStoreMargin(
    String? averageUnitCostFunctional,
    String? storeMarginPercent,
  ) {
    final c = averageUnitCostFunctional?.trim();
    final m = storeMarginPercent?.trim();
    if (c == null || c.isEmpty || m == null || m.isEmpty) return null;
    final md = double.tryParse(m.replaceAll(',', '.'));
    if (md == null) return null;
    final factor = ((100 + md) / 100).toString();
    return MoneyStringMath.multiply(c, factor, fractionDigits: 2);
  }

  static String get afterPurchaseSnackMessage =>
      'Compra registrada.\n\n'
      'El precio de lista del catálogo no se actualiza solo. '
      'Revisá margen y precio en Catálogo si hace falta.';

  /// Tras registrar compra online: costo + precio lista vía `suggestedPrice` del API (si aplica margen).
  static String get afterPurchaseWithCatalogCostUpdatedSnackMessage =>
      'Compra registrada.\n\n'
      'Se actualizó el costo en ficha con el unitario de esta recepción. '
      'Si el producto usa margen (tienda o propio), el precio de lista se alineó '
      'al valor sugerido que devuelve el servidor tras el cambio de costo.\n\n'
      'Los productos en precio manual solo actualizaron costo: revisá el precio de lista en Catálogo.';

  static String get stockDetailPolicyLine =>
      'Tras una compra el costo medio de depósito se actualiza aquí; '
      'el precio de lista se edita en Catálogo (el servidor no lo cambia en silencio).';

  static String get catalogSuggestedUsesProductCost =>
      'El «Sugerido API» en catálogo usa Product.cost, no el costo medio de inventario.';
}
