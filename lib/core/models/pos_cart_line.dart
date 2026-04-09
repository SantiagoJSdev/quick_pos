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

  String get lineTotalDocument =>
      MoneyStringMath.multiply(documentUnitPrice, quantity);
}
