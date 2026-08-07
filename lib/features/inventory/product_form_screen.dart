import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/uploads_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/catalog_product.dart';
import '../../core/photos/pending_product_photo_upload_entry.dart';
import '../../core/models/supplier.dart';
import '../../core/pos/post_purchase_price_hint.dart';
import '../../core/storage/local_prefs.dart';
import 'product_initial_stock_sheet.dart';
import '../sale/barcode_scanner_screen.dart';

const _currencies = ['USD', 'VES', 'EUR'];
final _decimal = RegExp(r'^\d+(\.\d+)?$');

bool _marginPercentInRange(String raw) {
  if (!_decimal.hasMatch(raw.trim())) return false;
  final v = double.tryParse(raw.trim());
  if (v == null) return false;
  return v >= 0 && v <= 999;
}

enum _NewProductStockChoice { soloProducto, conStockInicial }

/// B5 — `POST /products` o `PATCH /products/:id`; alta con stock → M7 `POST /products-with-stock`.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
    required this.suppliersApi,
    required this.localPrefs,
    this.storesApi,
    this.catalogInvalidationBus,
    this.uploadsApi,
    this.existing,
    this.initialBarcode,
    this.shellOnline = true,
  });

  final String storeId;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;
  final LocalPrefs localPrefs;

  /// Opcional: margen de tienda para calcular precio de lista vacío al editar (`USE_STORE_DEFAULT`).
  final StoresApi? storesApi;
  final CatalogInvalidationBus? catalogInvalidationBus;
  final UploadsApi? uploadsApi;

  final CatalogProduct? existing;

  /// Solo alta: precarga el campo código de barras (p. ej. escaneo desde Stock/Catálogo).
  final String? initialBarcode;

  /// Desde [MainShell]: evita APIs al abrir el formulario y al confirmar stock inicial.
  final bool shellOnline;

  bool get isEdit => existing != null;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _sku = TextEditingController();
  final _name = TextEditingController();
  final _barcode = TextEditingController();
  final _price = TextEditingController();
  final _cost = TextEditingController();
  final _unit = TextEditingController();
  final _description = TextEditingController();
  final _marginPercentOverride = TextEditingController();
  String _currency = 'USD';
  String _type = 'GOODS';
  String _pricingMode = 'USE_STORE_DEFAULT';
  bool _allowNoBarcode = false;
  bool _loading = false;
  String? _error;
  final ImagePicker _picker = ImagePicker();
  String? _photoLocalPath;

  List<Supplier> _suppliers = [];
  bool _suppliersLoading = true;
  String? _suppliersLoadError;
  String? _supplierId;
  String? _storeDefaultMarginPercent;

  /// Ficha al abrir el formulario (para inferir % si el margen de tienda aún no cargó).
  String? _openingListPrice;
  String? _openingCost;

  bool get _isByWeightUnit => _unit.text.trim().toUpperCase() == 'KG';

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    final rawSid = p?.supplierId?.trim();
    _supplierId = (rawSid == null || rawSid.isEmpty) ? null : rawSid;
    if (p != null) {
      _sku.text = p.sku;
      _name.text = p.name;
      if (p.barcode != null) _barcode.text = p.barcode!;
      _price.text = p.price;
      _cost.text = p.cost;
      _openingListPrice = p.price;
      _openingCost = p.cost;
      _currency = _currencies.contains(p.currency) ? p.currency : 'USD';
      _type = p.type ?? 'GOODS';
      if (p.unit != null) _unit.text = p.unit!;
      if (p.description != null) _description.text = p.description!;
      _allowNoBarcode = p.barcode == null || p.barcode!.isEmpty;
      final pm = p.pricingMode?.trim();
      _pricingMode = (pm == null || pm.isEmpty) ? 'USE_STORE_DEFAULT' : pm;
      if (p.marginPercentOverride != null) {
        _marginPercentOverride.text = p.marginPercentOverride!;
      }
    } else {
      final b = widget.initialBarcode?.trim();
      if (b != null && b.isNotEmpty) {
        _barcode.text = b;
        _allowNoBarcode = false;
      }
    }
    _cost.addListener(_syncListPriceFromCostAndMargin);
    _marginPercentOverride.addListener(_syncListPriceFromCostAndMargin);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncListPriceFromCostAndMargin();
      unawaited(_prefetchStoreDefaultMargin());
      unawaited(_loadSuppliers());
      if (!widget.isEdit) {
        final b = widget.initialBarcode?.trim();
        if (b != null && b.isNotEmpty) {
          unawaited(_checkBarcodeFieldForDuplicate());
        }
      }
    });
  }

  bool get _listPriceFollowsMargin =>
      _pricingMode == 'USE_STORE_DEFAULT' ||
      _pricingMode == 'USE_PRODUCT_OVERRIDE';

  /// % margen implícito en precio/costo (p. ej. lista 2 y costo 1 → 100).
  static String? _marginPercentFromPriceAndCost(String? price, String? cost) {
    final pr = double.tryParse(
      price?.trim().replaceAll(',', '.') ?? '',
    );
    final co = double.tryParse(
      cost?.trim().replaceAll(',', '.') ?? '',
    );
    if (pr == null || co == null || co <= 0) return null;
    final pct = ((pr / co) - 1) * 100;
    if (pct < 0) return '0';
    final s = pct.toStringAsFixed(4);
    return s.contains('.')
        ? s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
        : s;
  }

  String? _marginPercentForListPrice() {
    if (_pricingMode == 'USE_PRODUCT_OVERRIDE') {
      final mo = _marginPercentOverride.text.trim();
      if (mo.isNotEmpty) return mo;
      return widget.existing?.marginPercentOverride?.trim();
    }
    if (_pricingMode == 'USE_STORE_DEFAULT') {
      final store = _storeDefaultMarginPercent?.trim();
      if (store != null && store.isNotEmpty) return store;
      final em = widget.existing?.effectiveMarginPercent?.trim();
      if (em != null && em.isNotEmpty) return em;
      final mc = widget.existing?.marginComputedPercent?.trim();
      if (mc != null && mc.isNotEmpty) return mc;
      final sug = widget.existing?.suggestedPrice?.trim();
      final baseCost = widget.existing?.cost.trim();
      if (sug != null &&
          sug.isNotEmpty &&
          baseCost != null &&
          baseCost.isNotEmpty) {
        final fromSug = _marginPercentFromPriceAndCost(sug, baseCost);
        if (fromSug != null) return fromSug;
      }
      return _marginPercentFromPriceAndCost(_openingListPrice, _openingCost);
    }
    return null;
  }

  /// Precio de lista = costo × (1 + margen/100) cuando aplica política M7.
  String? _suggestedListPriceFromCost(String cost) {
    final margin = _marginPercentForListPrice();
    if (margin == null || margin.isEmpty) return null;
    return PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
      cost,
      margin,
    );
  }

  void _syncListPriceFromCostAndMargin() {
    if (!_listPriceFollowsMargin || _loading) return;
    final cost = _cost.text.trim();
    if (!_decimal.hasMatch(cost)) return;
    final sug = _suggestedListPriceFromCost(cost);
    if (sug == null) return;
    if (_price.text.trim() == sug) return;
    _price.text = sug;
    if (mounted) setState(() {});
  }

  /// Al guardar con margen: siempre ignora el valor viejo del input y usa costo × margen.
  String? _resolveListPriceForMarginPolicy(String cost) {
    if (!_listPriceFollowsMargin) return null;
    if (_pricingMode == 'USE_PRODUCT_OVERRIDE') {
      final mo = _marginPercentOverride.text.trim();
      if (!_marginPercentInRange(mo)) return null;
      return PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
        cost,
        mo,
      );
    }
    final margin = _marginPercentForListPrice();
    if (margin == null || margin.isEmpty) return null;
    return PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
      cost,
      margin,
    );
  }

  CatalogProduct _catalogWithPrice(CatalogProduct base, String price) {
    return CatalogProduct(
      id: base.id,
      sku: base.sku,
      name: base.name,
      barcode: base.barcode,
      description: base.description,
      type: base.type,
      price: price,
      cost: base.cost,
      currency: base.currency,
      active: base.active,
      unit: base.unit,
      supplierId: base.supplierId,
      pricingMode: base.pricingMode,
      marginPercentOverride: base.marginPercentOverride,
      effectiveMarginPercent: base.effectiveMarginPercent,
      marginComputedPercent: base.marginComputedPercent,
      suggestedPrice: base.suggestedPrice,
      imageUrl: base.imageUrl,
    );
  }

  Future<void> _prefetchStoreDefaultMargin() async {
    final cached = await widget.localPrefs.loadBusinessSettingsCache(
      widget.storeId,
    );
    final m0 = cached?.defaultMarginPercent?.trim();
    if (m0 != null && m0.isNotEmpty && mounted) {
      setState(() {
        _storeDefaultMarginPercent = m0;
        _syncListPriceFromCostAndMargin();
      });
    }
    final api = widget.storesApi;
    if (api == null || !widget.shellOnline) return;
    try {
      final bs = await api.getBusinessSettings(widget.storeId);
      if (!mounted) return;
      final m = bs.defaultMarginPercent?.trim();
      setState(() {
        _storeDefaultMarginPercent = (m == null || m.isEmpty) ? null : m;
        if (m != null && m.isNotEmpty) {
          _syncListPriceFromCostAndMargin();
        }
      });
    } catch (_) {}
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _suppliersLoading = true;
      _suppliersLoadError = null;
    });
    if (!widget.shellOnline) {
      final local = await widget.localPrefs.getLocalSuppliers();
      if (!mounted) return;
      final mapped =
          local
              .map(
                (x) => Supplier(
                  id: x.id,
                  storeId: widget.storeId,
                  name: x.name,
                  active: true,
                ),
              )
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
      setState(() {
        _suppliers = mapped;
        _suppliersLoading = false;
        _suppliersLoadError = mapped.isEmpty
            ? 'Sin proveedores en caché.'
            : null;
      });
      return;
    }
    try {
      final all = <Supplier>[];
      String? cursor;
      for (var i = 0; i < 40; i++) {
        final page = await widget.suppliersApi.listSuppliers(
          widget.storeId,
          cursor: cursor,
          limit: 200,
          active: 'true',
        );
        all.addAll(page.items);
        final next = page.nextCursor?.trim();
        if (next == null || next.isEmpty) break;
        cursor = next;
      }
      all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _suppliers = all;
        _suppliersLoading = false;
      });
    } on ApiError catch (e) {
      await _applySuppliersFromLocalCache(e.userMessageForSupport);
    } catch (e) {
      await _applySuppliersFromLocalCache(e.toString());
    }
  }

  Future<void> _applySuppliersFromLocalCache(String remoteErr) async {
    final local = await widget.localPrefs.getLocalSuppliers();
    if (!mounted) return;
    final mapped =
        local
            .map(
              (x) => Supplier(
                id: x.id,
                storeId: widget.storeId,
                name: x.name,
                active: true,
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    setState(() {
      _suppliers = mapped;
      _suppliersLoading = false;
      _suppliersLoadError = mapped.isEmpty ? remoteErr : null;
    });
  }

  List<DropdownMenuItem<String?>> _supplierDropdownItems() {
    final out = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('Sin proveedor'),
      ),
    ];
    final orphan = _supplierId;
    if (orphan != null && !_suppliers.any((s) => s.id == orphan)) {
      final short = orphan.length > 12 ? '${orphan.substring(0, 8)}…' : orphan;
      out.add(
        DropdownMenuItem<String?>(
          value: orphan,
          child: Text('Proveedor asignado ($short)'),
        ),
      );
    }
    for (final s in _suppliers) {
      out.add(
        DropdownMenuItem<String?>(
          value: s.id,
          child: Text(s.name, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return out;
  }

  Future<CatalogProduct?> _findProductByBarcode(String raw) async {
    final c = raw.trim().toLowerCase();
    if (c.isEmpty) return null;
    final excludeId = widget.existing?.id.trim();

    CatalogProduct? matchIn(Iterable<CatalogProduct> list) {
      for (final p in list) {
        if (excludeId != null &&
            excludeId.isNotEmpty &&
            p.id.trim() == excludeId) {
          continue;
        }
        final b = p.barcode?.trim().toLowerCase();
        if (b != null && b.isNotEmpty && b == c) return p;
      }
      return null;
    }

    // Alta/edición online-only: consultar catálogo del servidor si hay red.
    if (widget.shellOnline) {
      try {
        final list = await widget.productsApi.listProducts(widget.storeId);
        if (!mounted) return null;
        await widget.localPrefs.saveCatalogProductsCache(list);
        return matchIn(list);
      } catch (_) {
        // Fallback a caché si el listado falla (sin crear offline).
      }
    }

    final cached = await widget.localPrefs.loadCatalogProductsCache();
    return matchIn(cached);
  }

  Future<void> _warnBarcodeAlreadyExists(CatalogProduct existing) async {
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código de barras ya registrado'),
        content: Text(
          'Ya existe el producto «${existing.name}»'
          '${existing.sku.trim().isNotEmpty ? ' (SKU ${existing.sku})' : ''} '
          'con este código de barras.\n\n'
          'No hace falta crear otro: podés editar el existente o usar otro código.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'clear'),
            child: const Text('Usar otro código'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'edit'),
            child: const Text('Editar existente'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'clear') {
      setState(() {
        _barcode.clear();
        _allowNoBarcode = false;
        _error = null;
      });
      return;
    }
    if (choice == 'edit') {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<Object?>(
          builder: (ctx) => ProductFormScreen(
            storeId: widget.storeId,
            productsApi: widget.productsApi,
            suppliersApi: widget.suppliersApi,
            localPrefs: widget.localPrefs,
            storesApi: widget.storesApi,
            catalogInvalidationBus: widget.catalogInvalidationBus,
            uploadsApi: widget.uploadsApi,
            shellOnline: widget.shellOnline,
            existing: existing,
          ),
        ),
      );
    }
  }

  Future<void> _checkBarcodeFieldForDuplicate() async {
    final code = _barcode.text.trim();
    if (code.isEmpty || _loading) return;
    final existing = await _findProductByBarcode(code);
    if (!mounted || existing == null) return;
    await _warnBarcodeAlreadyExists(existing);
  }

  Future<void> _scanBarcodeField() async {
    if (!BarcodeScannerScreen.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El escáner solo está disponible en Android e iOS.'),
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final code = await BarcodeScannerScreen.open(context);
    if (!mounted || code == null || code.isEmpty) return;
    final trimmed = code.trim();
    setState(() {
      _barcode.text = trimmed;
      _allowNoBarcode = false;
      _error = null;
    });
    final existing = await _findProductByBarcode(trimmed);
    if (!mounted || existing == null) return;
    await _warnBarcodeAlreadyExists(existing);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final x = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1080,
      );
      if (!mounted || x == null) return;
      setState(() => _photoLocalPath = x.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo cargar foto: $e')));
    }
  }

  void _clearPhoto() {
    setState(() => _photoLocalPath = null);
  }

  Future<void> _queuePhotoUploadIfAny(String productId) async {
    final path = _photoLocalPath?.trim();
    final pid = productId.trim();
    if (path == null || path.isEmpty || pid.isEmpty) return;
    await widget.localPrefs.appendPendingProductPhotoUpload(
      PendingProductPhotoUploadEntry(
        opId: ClientMutationId.newId(),
        storeId: widget.storeId,
        productId: pid,
        localFilePath: path,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  }

  /// Tras guardar la ficha online: sube e asocia la foto de inmediato si hay [uploadsApi].
  Future<CatalogProduct> _applyPhotoAfterSaveIfNeeded(
    CatalogProduct baseline,
    String productId,
  ) async {
    final path = _photoLocalPath?.trim();
    if (path == null || path.isEmpty) return baseline;
    final pid = productId.trim();
    if (pid.isEmpty) return baseline;
    final upApi = widget.uploadsApi;
    if (upApi != null) {
      try {
        final upload = await upApi.uploadProductImage(
          widget.storeId,
          filePath: path,
        );
        final url = upload.url.trim();
        if (url.isEmpty) {
          await _queuePhotoUploadIfAny(pid);
          return baseline;
        }
        final withImg = await widget.productsApi.associateProductImage(
          widget.storeId,
          pid,
          imageUrl: url,
        );
        if (mounted) setState(() => _photoLocalPath = null);
        return withImg;
      } catch (_) {
        await _queuePhotoUploadIfAny(pid);
        return baseline;
      }
    }
    await _queuePhotoUploadIfAny(pid);
    return baseline;
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
    _cost.removeListener(_syncListPriceFromCostAndMargin);
    _marginPercentOverride.removeListener(_syncListPriceFromCostAndMargin);
    _cost.dispose();
    _unit.dispose();
    _description.dispose();
    _marginPercentOverride.dispose();
    super.dispose();
  }

  String _marginSnapshotFromExisting() {
    final p = widget.existing;
    if (p == null) return '';
    final parts = <String>[];
    final em = p.effectiveMarginPercent?.trim();
    if (em != null && em.isNotEmpty) {
      parts.add('Margen efectivo (última respuesta del servidor): $em%');
    }
    final sp = p.suggestedPrice?.trim();
    if (sp != null && sp.isNotEmpty) {
      parts.add('Precio sugerido: $sp ${p.currency}');
    }
    final mc = p.marginComputedPercent?.trim();
    if (mc != null && mc.isNotEmpty) {
      parts.add('Margen precio/costo: $mc%');
    }
    return parts.join(' · ');
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!widget.shellOnline) {
      setState(() {
        _error =
            'Para crear o editar productos necesitás conexión con el servidor. '
            'Activá el modo online e intentá de nuevo.';
      });
      return;
    }
    final skuInput = _sku.text.trim();
    final name = _name.text.trim();
    final barcode = _barcode.text.trim();
    final priceRaw = _price.text.trim();
    final cost = _cost.text.trim();

    if (name.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    if (barcode.isEmpty && !_allowNoBarcode) {
      setState(() {
        _error =
            'Código de barras vacío: activá “Permitir sin código de barras” si '
            'este producto solo se venderá por búsqueda manual.';
      });
      return;
    }
    if (barcode.isNotEmpty) {
      final existingByBarcode = await _findProductByBarcode(barcode);
      if (!mounted) return;
      if (existingByBarcode != null) {
        setState(() {
          _error =
              'Ya existe «${existingByBarcode.name}»'
              '${existingByBarcode.sku.trim().isNotEmpty ? ' (SKU ${existingByBarcode.sku})' : ''} '
              'con este código de barras. Editá ese producto o usá otro código.';
        });
        return;
      }
    }
    if (!_decimal.hasMatch(cost)) {
      setState(
        () => _error = 'El costo debe ser un número decimal válido (ej. 4.99).',
      );
      return;
    }
    if (_pricingMode == 'USE_PRODUCT_OVERRIDE') {
      final mo = _marginPercentOverride.text.trim();
      if (!_marginPercentInRange(mo)) {
        setState(
          () => _error = 'Margen propio: número entre 0 y 999 (ej. 25 o 12.5).',
        );
        return;
      }
    }

    late final String listPriceForModel;
    if (_pricingMode == 'MANUAL_PRICE') {
      if (priceRaw.isEmpty) {
        setState(
          () => _error = 'En precio manual debés indicar el precio de lista.',
        );
        return;
      }
      if (!_decimal.hasMatch(priceRaw)) {
        setState(
          () => _error = 'Precio de lista no válido (ej. 4.99).',
        );
        return;
      }
      listPriceForModel = priceRaw;
    } else {
      final sug = _resolveListPriceForMarginPolicy(cost);
      if (sug == null) {
        setState(
          () => _error = _pricingMode == 'USE_PRODUCT_OVERRIDE'
              ? 'No se pudo calcular el precio desde costo y margen propio.'
              : 'No hay margen de tienda disponible. Conectate, configurá el margen '
                  'en ajustes de negocio, o usá margen propio / precio manual.',
        );
        return;
      }
      listPriceForModel = sug;
      _price.text = sug;
    }

    // Alta: SKU vacío → no se envía; backend asigna SKU-000xxx (`BACKEND_PRODUCT_SKU_BARCODE.md`).
    // Edición: PATCH exige SKU no vacío si se envía → conservamos el actual si el campo quedó vacío.
    final skuForModel = widget.isEdit
        ? (skuInput.isNotEmpty ? skuInput : widget.existing!.sku)
        : skuInput;
    if (widget.isEdit && skuForModel.trim().isEmpty) {
      setState(() => _error = 'El SKU no puede quedar vacío al editar.');
      return;
    }

    final product = CatalogProduct(
      id: widget.existing?.id ?? '',
      sku: skuForModel,
      name: name,
      barcode: barcode.isEmpty ? null : barcode,
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      type: _type,
      price: listPriceForModel,
      cost: cost,
      currency: _currency,
      active: widget.existing?.active ?? true,
      unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      supplierId: _supplierId,
      pricingMode: _type == 'SERVICE'
          ? 'MANUAL_PRICE'
          : (_pricingMode == 'USE_STORE_DEFAULT' ? null : _pricingMode),
      marginPercentOverride: _pricingMode == 'USE_PRODUCT_OVERRIDE'
          ? _marginPercentOverride.text.trim()
          : null,
      effectiveMarginPercent: widget.existing?.effectiveMarginPercent,
      marginComputedPercent: widget.existing?.marginComputedPercent,
      suggestedPrice: widget.existing?.suggestedPrice,
      imageUrl: widget.existing?.imageUrl,
    );

    if (widget.isEdit) {
      setState(() => _loading = true);
      try {
        final hadLocalPhotoPick =
            _photoLocalPath != null && _photoLocalPath!.trim().isNotEmpty;
        var updated = await widget.productsApi.updateProduct(
          widget.storeId,
          widget.existing!.id,
          product.toPatchBody(),
        );
        updated = updated.withResolvedSupplierId(product.supplierId);
        var forCache = await _applyPhotoAfterSaveIfNeeded(
          updated,
          widget.existing!.id,
        );
        forCache = forCache.withResolvedSupplierId(product.supplierId);
        if (_listPriceFollowsMargin) {
          forCache = _catalogWithPrice(forCache, listPriceForModel);
        }
        if (!mounted) return;
        final cached = await widget.localPrefs.loadCatalogProductsCache();
        final i = cached.indexWhere((x) => x.id == widget.existing!.id);
        if (i >= 0) {
          cached[i] = forCache;
          await widget.localPrefs.saveCatalogProductsCache(cached);
        }
        widget.catalogInvalidationBus?.invalidateFromLocalMutation(
          productIds: {widget.existing!.id},
        );
        if (!mounted) return;
        final photoSaved =
            hadLocalPhotoPick &&
            (forCache.imageUrl?.trim().isNotEmpty ?? false);
        final photoQueued = hadLocalPhotoPick && !photoSaved;
        final priceNote = _listPriceFollowsMargin
            ? ' · precio de lista alineado al costo y margen'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Producto actualizado$priceNote'
              '${_listPriceFollowsMargin ? ' ($listPriceForModel $_currency)' : ''}'
              '${photoSaved ? ' · foto guardada' : ''}'
              '${photoQueued ? ' · foto en cola' : ''}',
            ),
          ),
        );
        Navigator.of(context).pop(forCache);
      } on ApiError catch (e) {
        if (!mounted) return;
        if (e.isLikelyTransportFailure) {
          setState(() {
            _error =
                'Sin conexión con el servidor. Los productos solo se pueden '
                'guardar online. Verificá la red e intentá de nuevo.';
          });
          return;
        }
        setState(() => _error = e.catalogConflictMessageEs);
      } catch (e) {
        if (!mounted) return;
        setState(
          () => _error = e is ApiError
              ? e.catalogConflictMessageEs
              : 'No se pudo guardar. Verificá la conexión.',
        );
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final choice = await showDialog<_NewProductStockChoice?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alta de producto'),
        content: const Text(
          'Solo ficha: se crea el artículo; el stock queda en 0 hasta un ajuste en '
          'Inventario → Stock.\n\n'
          'Con stock inicial: una sola solicitud crea la ficha y registra la entrada. '
          'Se envía la cabecera Idempotency-Key y un opId en el movimiento (ver '
          'docs §13.6b).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _NewProductStockChoice.soloProducto),
            child: const Text('Solo producto'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, _NewProductStockChoice.conStockInicial),
            child: const Text('Con stock inicial'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == null) return;

    if (choice == _NewProductStockChoice.soloProducto) {
      setState(() => _loading = true);
      try {
        var created = await widget.productsApi.createProduct(
          widget.storeId,
          product.toCreateBody(),
        );
        created = await _applyPhotoAfterSaveIfNeeded(created, created.id);
        if (!mounted) return;
        final cached = await widget.localPrefs.loadCatalogProductsCache();
        cached.removeWhere((x) => x.id == created.id);
        cached.add(created);
        await widget.localPrefs.saveCatalogProductsCache(cached);
        widget.catalogInvalidationBus?.invalidateFromLocalMutation(
          productIds: {created.id},
        );
        if (!mounted) return;
        final photoSaved = created.imageUrl?.trim().isNotEmpty ?? false;
        final stillQueued =
            _photoLocalPath != null && _photoLocalPath!.trim().isNotEmpty;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              photoSaved
                  ? 'Producto creado · SKU ${created.sku} · foto guardada'
                  : stillQueued
                  ? 'Producto creado · SKU ${created.sku} · foto en cola'
                  : 'Producto creado · SKU ${created.sku}',
            ),
          ),
        );
        Navigator.of(context).pop(created);
      } on ApiError catch (e) {
        if (!mounted) return;
        if (e.isLikelyTransportFailure) {
          setState(() {
            _error =
                'Sin conexión con el servidor. Los productos solo se pueden '
                'crear online. Verificá la red e intentá de nuevo.';
          });
          return;
        }
        setState(() => _error = e.catalogConflictMessageEs);
      } catch (e) {
        if (!mounted) return;
        setState(
          () => _error = e is ApiError
              ? e.catalogConflictMessageEs
              : 'No se pudo guardar. Verificá la conexión.',
        );
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => ProductInitialStockBottomSheet(
        storeId: widget.storeId,
        productsApi: widget.productsApi,
        localPrefs: widget.localPrefs,
        productDraft: product,
        catalogInvalidationBus: widget.catalogInvalidationBus,
        shellOnline: widget.shellOnline,
      ),
    );
    if (!mounted) return;
    if (result == null || result == false) return;

    if (_photoLocalPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Producto con stock creado. La foto queda en preview local pendiente de integración backend.',
          ),
        ),
      );
    }
    // Sheet devolvió el producto creado (o true) → salir del formulario.
    Navigator.of(context).pop(result is CatalogProduct ? result : true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Editar producto' : 'Nuevo producto'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _sku,
            decoration: InputDecoration(
              labelText: 'SKU (referencia interna)',
              helperText: widget.isEdit
                  ? 'Obligatorio al guardar. Independiente del código de barras.'
                  : 'Opcional al crear: vacío → el servidor asigna SKU-000001, …',
              border: const OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Foto del producto (preview local)',
              helperText:
                  'No bloquea guardado. Upload a backend se integrará cuando exista endpoint.',
              border: OutlineInputBorder(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _photoLocalPath == null
                      ? Center(
                          child: Text(
                            'Sin foto seleccionada',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Image.file(File(_photoLocalPath!), fit: BoxFit.cover),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Galería'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Cámara'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Quitar foto',
                      onPressed: (_loading || _photoLocalPath == null)
                          ? null
                          : _clearPhoto,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_suppliersLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else ...[
            if (_suppliersLoadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _suppliersLoadError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Proveedor (opcional)',
                helperText:
                    'Misma tienda que el catálogo. Solo proveedores activos.',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _supplierId,
                  isExpanded: true,
                  items: _supplierDropdownItems(),
                  onChanged: _loading
                      ? null
                      : (v) => setState(() => _supplierId = v),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _barcode,
            decoration: InputDecoration(
              labelText: 'Código de barras (EAN / UPC)',
              hintText: 'Escribí/pegá el código o usá el ícono para escanear.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear',
                onPressed: _loading ? null : _scanBarcodeField,
              ),
            ),
            keyboardType: TextInputType.text,
            enabled: !_loading,
            textInputAction: TextInputAction.done,
            onEditingComplete: () {
              FocusManager.instance.primaryFocus?.unfocus();
              unawaited(_checkBarcodeFieldForDuplicate());
            },
          ),
          SwitchListTile(
            title: const Text('Permitir sin código de barras'),
            subtitle: const Text(
              'Solo si vas a venderlo siempre buscando por nombre/SKU en caja.',
            ),
            value: _allowNoBarcode,
            onChanged: _loading
                ? null
                : (v) => setState(() => _allowNoBarcode = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _price,
                  decoration: InputDecoration(
                    labelText: 'Precio lista',
                    border: const OutlineInputBorder(),
                    helperText: _listPriceFollowsMargin
                        ? 'Calculado desde costo y margen al cambiar el costo o al guardar.'
                        : null,
                    filled: _listPriceFollowsMargin,
                    fillColor: _listPriceFollowsMargin
                        ? Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                        : null,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  readOnly: _listPriceFollowsMargin,
                  showCursor: !_listPriceFollowsMargin,
                  enableInteractiveSelection: !_listPriceFollowsMargin,
                  enabled: !_loading,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _cost,
                  decoration: const InputDecoration(
                    labelText: 'Costo',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  enabled: !_loading,
                  onChanged: (_) => _syncListPriceFromCostAndMargin(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Moneda',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _currency,
                isExpanded: true,
                items: [
                  for (final c in _currencies)
                    DropdownMenuItem(value: c, child: Text(c)),
                ],
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v != null) setState(() => _currency = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Política de margen',
              helperText:
                  'Con margen de tienda o propio, el precio de lista sigue al costo. '
                  'En precio manual lo definís vos.',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _pricingMode,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: 'USE_STORE_DEFAULT',
                    child: Text('Margen de la tienda'),
                  ),
                  DropdownMenuItem(
                    value: 'USE_PRODUCT_OVERRIDE',
                    child: Text('Margen propio (%)'),
                  ),
                  DropdownMenuItem(
                    value: 'MANUAL_PRICE',
                    child: Text('Precio manual (sin sugerido por margen)'),
                  ),
                ],
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v != null) {
                          setState(() => _pricingMode = v);
                          _syncListPriceFromCostAndMargin();
                        }
                      },
              ),
            ),
          ),
          if (_pricingMode == 'USE_PRODUCT_OVERRIDE') ...[
            const SizedBox(height: 12),
            TextField(
              controller: _marginPercentOverride,
              decoration: const InputDecoration(
                labelText: 'Margen % sobre costo',
                hintText: 'ej. 25',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              enabled: !_loading,
            ),
          ],
          if (widget.isEdit) ...[
            Builder(
              builder: (context) {
                final snap = _marginSnapshotFromExisting();
                if (snap.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    snap,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Tipo',
              border: OutlineInputBorder(),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _type,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'GOODS', child: Text('GOODS')),
                  DropdownMenuItem(value: 'SERVICE', child: Text('SERVICE')),
                ],
                onChanged: _loading
                    ? null
                    : (v) {
                        if (v == null) return;
                        setState(() {
                          _type = v;
                          // Avance / servicios cobrados en POS: precio manual.
                          if (v == 'SERVICE') {
                            _pricingMode = 'MANUAL_PRICE';
                            if (_price.text.trim().isEmpty ||
                                (double.tryParse(
                                          _price.text
                                              .trim()
                                              .replaceAll(',', '.'),
                                        ) ??
                                        0) <=
                                    0) {
                              _price.text = '0';
                            }
                          }
                        });
                      },
              ),
            ),
          ),
          if (_type == 'SERVICE') ...[
            const SizedBox(height: 8),
            Text(
              'Servicio (p. ej. avance de efectivo): en el POS se pedirá el '
              'monto del avance y se cobrará avance + comisión 10%. '
              'Usá precio de lista 0 y modo MANUAL_PRICE.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            value: _isByWeightUnit,
            onChanged: _loading
                ? null
                : (v) {
                    setState(() {
                      if (v) {
                        _unit.text = 'KG';
                        if (_type == 'SERVICE') {
                          _type = 'GOODS';
                        }
                      } else if (_unit.text.trim().toUpperCase() == 'KG') {
                        _unit.clear();
                      }
                    });
                  },
            title: const Text('Producto por peso (charcutería)'),
            subtitle: const Text(
              'Activa `unit = KG` para usar “Agregar por peso” en POS.',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _unit,
            decoration: const InputDecoration(
              labelText: 'Unidad (opcional)',
              hintText: 'unidad, KG, …',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            enabled: !_loading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _loading ? null : _save,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.isEdit ? 'Guardar cambios' : 'Crear producto'),
          ),
        ],
      ),
    );
  }
}
