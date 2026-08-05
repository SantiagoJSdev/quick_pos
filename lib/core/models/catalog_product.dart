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
    this.blockSaleWithoutStock = false,
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

  /// B1 — no vender sin stock (salvo PIN supervisor en app).
  final bool blockSaleWithoutStock;

  /// `MANUAL_PRICE` fija lista a mano; el resto (incl. modo vacío / tienda) usa margen para orientar lista.
  bool get listPriceFollowsMarginPolicy {
    final m = pricingMode?.trim() ?? '';
    return m != 'MANUAL_PRICE';
  }

  /// Servicio con precio manual en cobro (p. ej. avance de efectivo → comisión %).
  bool get isPosCashAdvanceService {
    final t = type?.trim().toUpperCase() ?? '';
    final pm = pricingMode?.trim().toUpperCase() ?? '';
    return t == 'SERVICE' && pm == 'MANUAL_PRICE';
  }

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
      supplierId: _supplierIdFromJson(json),
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
      blockSaleWithoutStock: _parseBool(
        json['blockSaleWithoutStock'],
        defaultValue: false,
      ),
    );
  }

  static bool _parseBool(dynamic v, {required bool defaultValue}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
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

  /// `supplierId` plano o relación `supplier: { id }` (según serialización Nest).
  static String? _supplierIdFromJson(Map<String, dynamic> json) {
    final flat = _parseOptionalId(json['supplierId']);
    if (flat != null) return flat;
    final raw = json['supplier'];
    if (raw is Map) {
      return _parseOptionalId(raw['id']);
    }
    return null;
  }

  /// Si la respuesta de PATCH/GET no trae `supplierId` pero el cliente envió uno,
  /// conservarlo para caché y UI (evita que el desplegable “vuelva atrás”).
  CatalogProduct withResolvedSupplierId(String? fromPatchOrRequest) {
    final cur = supplierId?.trim();
    if (cur != null && cur.isNotEmpty) return this;
    final p = fromPatchOrRequest?.trim();
    if (p == null || p.isEmpty) return this;
    return CatalogProduct(
      id: id,
      sku: sku,
      name: name,
      barcode: barcode,
      description: description,
      type: type,
      price: price,
      cost: cost,
      currency: currency,
      active: active,
      unit: unit,
      supplierId: p,
      pricingMode: pricingMode,
      marginPercentOverride: marginPercentOverride,
      effectiveMarginPercent: effectiveMarginPercent,
      marginComputedPercent: marginComputedPercent,
      suggestedPrice: suggestedPrice,
      imageUrl: imageUrl,
      blockSaleWithoutStock: blockSaleWithoutStock,
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

  /// `PATCH /products/:id` — `sku` no puede ir vacío si se envía.
  ///
  /// No incluir claves con valor JSON `null` para strings opcionales: varios
  /// backends hacen `dto.campo.trim()` y rompen con 500 si el cuerpo trae
  /// `"campo": null`. `barcode` vacío se envía como `""` (misma intención que
  /// limpiar sin usar `null`). Sin proveedor: se omite `supplierId`. Sin
  /// override de margen: se omite `marginPercentOverride`.
  /// Si [applySuggestedListPrice] es true (M7), el servidor alinea `price` al
  /// sugerido según costo y margen; no enviar `price` en el mismo PATCH.
  Map<String, dynamic> toPatchBody({bool applySuggestedListPrice = false}) {
    final skuTrim = sku.trim();
    final nameTrim = name.trim();
    final priceTrim = price.trim();
    final costTrim = cost.trim();
    final m = <String, dynamic>{
      'sku': skuTrim,
      'name': nameTrim,
      'cost': costTrim.isEmpty ? '0' : costTrim,
      'currency': currency.trim(),
    };
    if (!applySuggestedListPrice) {
      m['price'] = priceTrim.isEmpty ? '0' : priceTrim;
    } else {
      m['applySuggestedListPrice'] = true;
    }
    final bc = barcode?.trim();
    m['barcode'] = (bc == null || bc.isEmpty) ? '' : bc;
    if (type != null && type!.trim().isNotEmpty) m['type'] = type!.trim();
    if (unit != null && unit!.trim().isNotEmpty) m['unit'] = unit!.trim();
    if (description != null) {
      m['description'] = description!.trim();
    }
    final sid = supplierId?.trim();
    if (sid != null && sid.isNotEmpty) {
      m['supplierId'] = sid;
    }
    final pm = (pricingMode?.trim().isEmpty ?? true)
        ? 'USE_STORE_DEFAULT'
        : pricingMode!.trim();
    m['pricingMode'] = pm;
    if (pm == 'USE_PRODUCT_OVERRIDE') {
      final o = marginPercentOverride?.trim();
      if (o != null && o.isNotEmpty) {
        m['marginPercentOverride'] = o;
      }
    }
    return m;
  }
}
