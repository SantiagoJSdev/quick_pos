import '../models/catalog_product.dart';
import 'money_string_math.dart';

/// Avance de efectivo: servicio con precio manual en el cobro.
///
/// Backend: `type=SERVICE`, `pricingMode=MANUAL_PRICE`, costo/precio lista 0.
/// En la venta: `qty=1` y `price` = comisión (no el monto del avance).
class PosCashAdvance {
  PosCashAdvance._();

  /// Comisión sobre el monto del avance (10%).
  static const String feeRate = '0.10';

  static const String feePercentLabel = '10%';

  /// Producto que dispara el sheet "Monto avance" en POS.
  ///
  /// Dispara si es `SERVICE` y además:
  /// - `pricingMode=MANUAL_PRICE`, o
  /// - precio de lista ~0 (caso típico al crear el avance sin setear modo).
  static bool isAdvanceProduct(CatalogProduct p) {
    final t = p.type?.trim().toUpperCase() ?? '';
    if (t != 'SERVICE') return false;
    final pm = p.pricingMode?.trim().toUpperCase() ?? '';
    if (pm == 'MANUAL_PRICE') return true;
    return _isZeroOrEmptyPrice(p.price);
  }

  static bool _isZeroOrEmptyPrice(String? raw) {
    final t = (raw ?? '').trim().replaceAll(',', '.');
    if (t.isEmpty) return true;
    final v = double.tryParse(t);
    if (v == null) return true;
    return v <= 0;
  }

  /// Comisión cobrada = [advanceAmount] × [feeRate] (2 decimales).
  static String feeFromAdvanceAmount(String advanceAmount) {
    return MoneyStringMath.multiply(
      advanceAmount.trim().replaceAll(',', '.'),
      feeRate,
      fractionDigits: 2,
    );
  }

  static bool isPositiveAmount(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return false;
    final v = double.tryParse(t);
    return v != null && v > 0;
  }
}
