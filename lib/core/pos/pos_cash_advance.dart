import '../models/catalog_product.dart';
import 'money_string_math.dart';

/// Avance de efectivo: servicio con precio manual en el cobro.
///
/// Producto `type=SERVICE` (+ `MANUAL_PRICE` / precio 0).
/// En la venta: `qty=1` y `price` = monto avance + comisión 10%.
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

  /// Comisión = [advanceAmount] × [feeRate] (2 decimales).
  static String feeFromAdvanceAmount(String advanceAmount) {
    return MoneyStringMath.multiply(
      advanceAmount.trim().replaceAll(',', '.'),
      feeRate,
      fractionDigits: 2,
    );
  }

  /// Total a cobrar en ticket = avance + comisión.
  static String totalChargeFromAdvanceAmount(String advanceAmount) {
    final base = advanceAmount.trim().replaceAll(',', '.');
    final fee = feeFromAdvanceAmount(base);
    return MoneyStringMath.sum([base, fee]);
  }

  static bool isPositiveAmount(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return false;
    final v = double.tryParse(t);
    return v != null && v > 0;
  }
}
