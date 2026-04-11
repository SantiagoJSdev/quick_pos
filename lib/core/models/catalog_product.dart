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
    this.supplierId,
    this.pricingMode,
    this.marginPercentOverride,
    this.effectiveMarginPercent,
    this.marginComputedPercent,
    this.suggestedPrice,
    this.imageUrl,
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

  /// Proveedor principal (`Product.supplierId`); misma tienda que `X-Store-Id`.
  final String? supplierId;

  /// `USE_STORE_DEFAULT` | `USE_PRODUCT_OVERRIDE` | `MANUAL_PRICE` (M7).
  final String? pricingMode;

  /// Margen % propio si [pricingMode] es override (M7).
  final String? marginPercentOverride;

  /// Solo respuesta API (derivado).
  final String? effectiveMarginPercent;

  /// Solo respuesta API (indicativo).
  final String? marginComputedPercent;

  /// Solo respuesta API.
  final String? suggestedPrice;

  /// Foto asociada al producto (URL relativa o absoluta según backend).
  final String? imageUrl;

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
      supplierId: _parseOptionalId(json['supplierId']),
      pricingMode: _parseOptionalString(json['pricingMode']),
      marginPercentOverride: _parseOptionalString(
        json['marginPercentOverride'],
      ),
      effectiveMarginPercent: _parseOptionalString(
        json['effectiveMarginPercent'],
      ),
      marginComputedPercent: _parseOptionalString(
        json['marginComputedPercent'],
      ),
      suggestedPrice: _parseOptionalString(json['suggestedPrice']),
      imageUrl: _parseOptionalString(json['imageUrl']),
    );
  }

  static String? _parseOptionalString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static String? _parseOptionalId(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
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
    final sid = supplierId?.trim();
    if (sid != null && sid.isNotEmpty) {
      m['supplierId'] = sid;
    }
    final pm = pricingMode?.trim();
    if (pm == 'MANUAL_PRICE') {
      m['pricingMode'] = 'MANUAL_PRICE';
    } else if (pm == 'USE_PRODUCT_OVERRIDE') {
      m['pricingMode'] = 'USE_PRODUCT_OVERRIDE';
      final o = marginPercentOverride?.trim();
      if (o != null && o.isNotEmpty) m['marginPercentOverride'] = o;
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
      m['description'] = description!.trim().isEmpty
          ? null
          : description!.trim();
    }
    final sid = supplierId?.trim();
    m['supplierId'] = (sid == null || sid.isEmpty) ? null : sid;
    final pm = (pricingMode?.trim().isEmpty ?? true)
        ? 'USE_STORE_DEFAULT'
        : pricingMode!.trim();
    m['pricingMode'] = pm;
    if (pm == 'USE_PRODUCT_OVERRIDE') {
      final o = marginPercentOverride?.trim();
      m['marginPercentOverride'] = (o != null && o.isNotEmpty) ? o : null;
    } else {
      m['marginPercentOverride'] = null;
    }
    return m;
  }
}
