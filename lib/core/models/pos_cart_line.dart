import '../pos/money_string_math.dart';

/// Línea del ticket: precio catálogo + precio en moneda documento (P2/P3).
class PosCartLine {
  PosCartLine({
    required this.productId,
    required this.name,
    required this.sku,
    required this.catalogUnitPrice,
    required this.catalogCurrency,
    required this.documentUnitPrice,
    required this.documentCurrencyCode,
    this.quantity = 1,
  });

  final String productId;
  final String name;
  final String sku;
  final String catalogUnitPrice;
  final String catalogCurrency;
  final String documentUnitPrice;
  final String documentCurrencyCode;
  int quantity;

  String get lineTotalDocument => MoneyStringMath.multiply(
        documentUnitPrice,
        quantity.toString(),
      );
}
