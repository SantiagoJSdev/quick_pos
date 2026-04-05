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

  /// `POST /products` — `docs/BACKEND_PRODUCT_SKU_BARCODE.md`: omitir `sku` vacío para que el backend asigne `SKU-000xxx`.
  Map<String, dynamic> toCreateBody() {
    final m = <String, dynamic>{
      'name': name,
      'price': price,
      'cost': cost,
      'currency': currency,
    };
    final skuTrim = sku.trim();
    if (skuTrim.isNotEmpty) {
      m['sku'] = skuTrim;
    }
    final bc = barcode?.trim();
    if (bc != null && bc.isNotEmpty) {
      m['barcode'] = bc;
    }
    if (type != null && type!.isNotEmpty) m['type'] = type;
    if (unit != null && unit!.trim().isNotEmpty) m['unit'] = unit!.trim();
    if (description != null && description!.trim().isNotEmpty) {
      m['description'] = description!.trim();
    }
    return m;
  }

  /// `PATCH /products/:id` — `sku` no puede ir vacío si se envía; `barcode` null limpia el código.
  Map<String, dynamic> toPatchBody() {
    final skuTrim = sku.trim();
    final m = <String, dynamic>{
      'sku': skuTrim,
      'name': name,
      'price': price,
      'cost': cost,
      'currency': currency,
      'barcode': (barcode == null || barcode!.trim().isEmpty)
          ? null
          : barcode!.trim(),
    };
    if (type != null && type!.isNotEmpty) m['type'] = type;
    if (unit != null && unit!.trim().isNotEmpty) m['unit'] = unit!.trim();
    if (description != null) {
      m['description'] =
          description!.trim().isEmpty ? null : description!.trim();
    }
    return m;
  }
}
