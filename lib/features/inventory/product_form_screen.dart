import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/supplier.dart';
import '../../core/pos/post_purchase_price_hint.dart';
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
    this.storesApi,
    this.catalogInvalidationBus,
    this.existing,
    this.initialBarcode,
  });

  final String storeId;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;

  /// Opcional: margen de tienda para calcular precio de lista vacío al editar (`USE_STORE_DEFAULT`).
  final StoresApi? storesApi;
  final CatalogInvalidationBus? catalogInvalidationBus;

  final CatalogProduct? existing;

  /// Solo alta: precarga el campo código de barras (p. ej. escaneo desde Stock/Catálogo).
  final String? initialBarcode;

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

  List<Supplier> _suppliers = [];
  bool _suppliersLoading = true;
  String? _suppliersLoadError;
  String? _supplierId;
  String? _storeDefaultMarginPercent;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadSuppliers());
      if (widget.isEdit && widget.storesApi != null) {
        unawaited(_prefetchStoreDefaultMargin());
      }
    });
  }

  Future<void> _prefetchStoreDefaultMargin() async {
    final api = widget.storesApi;
    if (api == null) return;
    try {
      final bs = await api.getBusinessSettings(widget.storeId);
      if (!mounted) return;
      final m = bs.defaultMarginPercent?.trim();
      setState(() {
        _storeDefaultMarginPercent = (m == null || m.isEmpty) ? null : m;
      });
    } catch (_) {}
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _suppliersLoading = true;
      _suppliersLoadError = null;
    });
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
      all.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _suppliers = all;
        _suppliersLoading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _suppliers = [];
        _suppliersLoading = false;
        _suppliersLoadError = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _suppliers = [];
        _suppliersLoading = false;
        _suppliersLoadError = e.toString();
      });
    }
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
          child: Text(
            s.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    return out;
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
    setState(() {
      _barcode.text = code;
      _allowNoBarcode = false;
    });
  }

  @override
  void dispose() {
    _sku.dispose();
    _name.dispose();
    _barcode.dispose();
    _price.dispose();
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
    if (!_decimal.hasMatch(cost)) {
      setState(() => _error = 'El costo debe ser un número decimal válido (ej. 4.99).');
      return;
    }
    if (!widget.isEdit) {
      if (priceRaw.isEmpty || !_decimal.hasMatch(priceRaw)) {
        setState(
          () => _error =
              'En un producto nuevo indicá precio de lista y costo.',
        );
        return;
      }
    } else {
      if (priceRaw.isNotEmpty && !_decimal.hasMatch(priceRaw)) {
        setState(
          () => _error =
              'Precio de lista no válido (o dejalo vacío para calcularlo desde costo y margen).',
        );
        return;
      }
    }
    if (_pricingMode == 'USE_PRODUCT_OVERRIDE') {
      final mo = _marginPercentOverride.text.trim();
      if (!_marginPercentInRange(mo)) {
        setState(
          () => _error =
              'Margen propio: número entre 0 y 999 (ej. 25 o 12.5).',
        );
        return;
      }
    }

    if (widget.isEdit &&
        priceRaw.isEmpty &&
        _pricingMode == 'USE_STORE_DEFAULT' &&
        widget.storesApi != null &&
        (_storeDefaultMarginPercent == null ||
            _storeDefaultMarginPercent!.trim().isEmpty)) {
      try {
        final bs = await widget.storesApi!.getBusinessSettings(widget.storeId);
        if (!mounted) return;
        final m = bs.defaultMarginPercent?.trim();
        setState(() {
          _storeDefaultMarginPercent = (m == null || m.isEmpty) ? null : m;
        });
      } catch (_) {}
    }

    late final String listPriceForModel;
    if (!widget.isEdit) {
      listPriceForModel = priceRaw;
    } else if (priceRaw.isNotEmpty) {
      listPriceForModel = priceRaw;
    } else if (_pricingMode == 'MANUAL_PRICE') {
      setState(
        () => _error =
            'En precio manual debés indicar el precio de lista.',
      );
      return;
    } else if (_pricingMode == 'USE_PRODUCT_OVERRIDE') {
      final mo = _marginPercentOverride.text.trim();
      final sug = PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
        cost,
        mo,
      );
      if (sug == null) {
        setState(
          () => _error =
              'No se pudo calcular el precio desde costo y margen propio.',
        );
        return;
      }
      listPriceForModel = sug;
    } else {
      final sm = _storeDefaultMarginPercent?.trim();
      if (sm == null || sm.isEmpty) {
        setState(
          () => _error =
              'Precio vacío: en Inicio → Configuración (clave) definí el margen '
              'de la tienda, elegí margen propio, o escribí el precio de lista.',
        );
        return;
      }
      final sug = PostPurchasePriceHint.suggestedListFromAverageCostAndStoreMargin(
        cost,
        sm,
      );
      if (sug == null) {
        setState(
          () => _error =
              'No se pudo calcular el precio desde costo y margen de tienda.',
        );
        return;
      }
      listPriceForModel = sug;
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
      pricingMode:
          _pricingMode == 'USE_STORE_DEFAULT' ? null : _pricingMode,
      marginPercentOverride: _pricingMode == 'USE_PRODUCT_OVERRIDE'
          ? _marginPercentOverride.text.trim()
          : null,
      effectiveMarginPercent: widget.existing?.effectiveMarginPercent,
      marginComputedPercent: widget.existing?.marginComputedPercent,
      suggestedPrice: widget.existing?.suggestedPrice,
    );

    if (widget.isEdit) {
      setState(() => _loading = true);
      try {
        await widget.productsApi.updateProduct(
          widget.storeId,
          widget.existing!.id,
          product.toPatchBody(),
        );
        if (!mounted) return;
        if (priceRaw.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Producto actualizado · precio de lista calculado: '
                '$listPriceForModel $_currency',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Producto actualizado')),
          );
        }
        Navigator.of(context).pop(true);
      } on ApiError catch (e) {
        if (!mounted) return;
        setState(() => _error = e.userMessageForSupport);
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
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
        final created = await widget.productsApi.createProduct(
          widget.storeId,
          product.toCreateBody(),
        );
        if (!mounted) return;
        widget.catalogInvalidationBus?.invalidateFromLocalMutation(
          productIds: {created.id},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Producto creado · SKU ${created.sku}')),
        );
        Navigator.of(context).pop(true);
      } on ApiError catch (e) {
        if (!mounted) return;
        setState(() => _error = e.userMessageForSupport);
      } catch (e) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => ProductInitialStockBottomSheet(
        storeId: widget.storeId,
        productsApi: widget.productsApi,
        productDraft: product,
        catalogInvalidationBus: widget.catalogInvalidationBus,
      ),
    );
    if (mounted && ok == true) Navigator.of(context).pop(true);
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
              hintText:
                  'Tocá el campo vacío o el ícono para abrir la cámara; podés escribir o pegar si ya hay código.',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear',
                onPressed: _loading ? null : _scanBarcodeField,
              ),
            ),
            keyboardType: TextInputType.text,
            enabled: !_loading,
            onTap: () {
              if (_loading || !BarcodeScannerScreen.isSupported) return;
              if (_barcode.text.trim().isNotEmpty) return;
              _scanBarcodeField();
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
                    helperText: widget.isEdit
                        ? 'Vacío al editar: se calcula como costo × (1 + margen) con margen propio o de tienda; no aplica en precio manual.'
                        : null,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  enabled: !_loading,
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
                  'Precio sugerido sobre costo (M7). El precio de lista lo definís arriba; '
                  'el servidor calcula sugeridos según la regla.',
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
                        if (v != null) setState(() => _pricingMode = v);
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                        if (v != null) setState(() => _type = v);
                      },
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _unit,
            decoration: const InputDecoration(
              labelText: 'Unidad (opcional)',
              hintText: 'unidad, kg, …',
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
