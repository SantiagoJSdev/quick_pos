/// Elemento de `GET /api/v1/products` (§13.5).
class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.sku,
    required this.name,
    this.barcode,
    this.description,
    this.type,
    required this.price,
    required this.cost,
    required this.currency,
    required this.active,
    this.unit,
  });

  final String id;
  final String sku;
  final String name;
  final String? barcode;
  final String? description;
  final String? type;
  final String price;
  final String cost;
  final String currency;
  final bool active;
  final String? unit;

  static CatalogProduct fromJson(Map<String, dynamic> json) {
    return CatalogProduct(
      id: json['id']?.toString() ?? '',
      sku: json['sku']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      barcode: json['barcode'] as String?,
      description: json['description'] as String?,
      type: json['type'] as String?,
      price: json['price']?.toString() ?? '0',
      cost: json['cost']?.toString() ?? '0',
      currency: json['currency']?.toString() ?? 'USD',
      active: json['active'] as bool? ?? true,
      unit: json['unit'] as String?,
    );
  }

  Map<String, dynamic> toCreateBody() {
    return {
      'sku': sku,
      'name': name,
      'price': price,
      'cost': cost,
      'currency': currency,
      if (barcode != null && barcode!.trim().isNotEmpty) 'barcode': barcode!.trim(),
      if (type != null && type!.isNotEmpty) 'type': type,
      if (unit != null && unit!.trim().isNotEmpty) 'unit': unit!.trim(),
      if (description != null && description!.trim().isNotEmpty)
        'description': description!.trim(),
    };
  }

  Map<String, dynamic> toPatchBody() {
    final m = <String, dynamic>{
      'sku': sku,
      'name': name,
      'price': price,
      'cost': cost,
      'currency': currency,
      if (barcode != null && barcode!.trim().isNotEmpty) 'barcode': barcode!.trim(),
      if (type != null && type!.isNotEmpty) 'type': type,
      if (unit != null && unit!.trim().isNotEmpty) 'unit': unit!.trim(),
    };
    if (description != null) {
      m['description'] =
          description!.trim().isEmpty ? null : description!.trim();
    }
    return m;
  }
}
