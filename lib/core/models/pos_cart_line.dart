import '../pos/money_string_math.dart';

/// Línea del ticket: precio catálogo + precio en moneda documento (P2/P3).
///
/// [quantity] es string decimal (ej. `1`, `2.5`) para peso u otros ítems.
class PosCartLine {
  PosCartLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.catalogUnitPrice,
    required this.catalogCurrency,
    required this.documentUnitPrice,
    required this.documentCurrencyCode,
    this.quantity = '1',
    this.isByWeight = false,
    this.displayGrams,
    this.pricePerKgFunctional,
    this.lineAmountFunctional,
    this.lineAmountDocument,
  });

  final String productId;
  final String name;
  final String sku;
  final String catalogUnitPrice;
  final String catalogCurrency;
  final String documentUnitPrice;
  final String documentCurrencyCode;
  String quantity;
  final bool isByWeight;
  final String? displayGrams;
  final String? pricePerKgFunctional;
  final String? lineAmountFunctional;
  final String? lineAmountDocument;

  static bool _positiveDecimal(String? s) {
    if (s == null) return false;
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return false;
    final v = double.tryParse(t) ?? 0;
    return v > 0;
  }

  /// Total línea en moneda documento. Por peso usa el monto fijado en el sheet
  /// ([lineAmountDocument]); si no, `precio unitario doc. × cantidad`.
  String get lineTotalDocument {
    if (isByWeight && _positiveDecimal(lineAmountDocument)) {
      return MoneyStringMath.multiply(
        '1',
        lineAmountDocument!.trim(),
        fractionDigits: 2,
      );
    }
    return MoneyStringMath.multiply(documentUnitPrice, quantity);
  }

  /// `POST /sales` `lines[].price`: por kg ajustado para que `quantity × price`
  /// coincida con [lineTotalDocument] cuando hay monto por peso acordado.
  String get documentUnitPriceForCheckout {
    if (isByWeight && _positiveDecimal(lineAmountDocument)) {
      final total = lineAmountDocument!.trim();
      final q = quantity.trim();
      if (q.isNotEmpty) {
        final qv = double.tryParse(q.replaceAll(',', '.')) ?? 0;
        if (qv > 0) {
          return MoneyStringMath.divide(total, q, fractionDigits: 10);
        }
      }
    }
    return documentUnitPrice;
  }
}
