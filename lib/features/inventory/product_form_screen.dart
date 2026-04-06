import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/supplier.dart';
import '../../core/storage/local_prefs.dart';
import 'inventory_adjustment_screen.dart';
import '../sale/barcode_scanner_screen.dart';

const _currencies = ['USD', 'VES', 'EUR'];
final _decimal = RegExp(r'^\d+(\.\d+)?$');

/// B5 — `POST /products` o `PATCH /products/:id`.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
    required this.suppliersApi,
    this.inventoryApi,
    this.localPrefs,
    this.existing,
    this.initialBarcode,
  });

  final String storeId;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;

  /// Si vienen ambos, tras **crear** producto se ofrece ir a B3 (stock inicial).
  final InventoryApi? inventoryApi;
  final LocalPrefs? localPrefs;

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
  String _currency = 'USD';
  String _type = 'GOODS';
  bool _allowNoBarcode = false;
  bool _loading = false;
  String? _error;

  List<Supplier> _suppliers = [];
  bool _suppliersLoading = true;
  String? _suppliersLoadError;
  String? _supplierId;

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
    } else {
      final b = widget.initialBarcode?.trim();
      if (b != null && b.isNotEmpty) {
        _barcode.text = b;
        _allowNoBarcode = false;
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadSuppliers());
    });
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

  void _copyBarcodeToSku() {
    final b = _barcode.text.trim();
    if (b.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cargá o escaneá un código de barras primero.'),
        ),
      );
      return;
    }
    setState(() => _sku.text = b);
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
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final skuInput = _sku.text.trim();
    final name = _name.text.trim();
    final barcode = _barcode.text.trim();
    final price = _price.text.trim();
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
    if (!_decimal.hasMatch(price) || !_decimal.hasMatch(cost)) {
      setState(() => _error = 'Precio y costo deben ser números decimales (ej. 4.99).');
      return;
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
      price: price,
      cost: cost,
      currency: _currency,
      active: widget.existing?.active ?? true,
      unit: _unit.text.trim().isEmpty ? null : _unit.text.trim(),
      supplierId: _supplierId,
    );

    setState(() => _loading = true);
    try {
      if (widget.isEdit) {
        await widget.productsApi.updateProduct(
          widget.storeId,
          widget.existing!.id,
          product.toPatchBody(),
        );
      } else {
        final created = await widget.productsApi.createProduct(
          widget.storeId,
          product.toCreateBody(),
        );
        if (!mounted) return;
        setState(() => _loading = false);
        await _finishAfterCreate(created);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto actualizado')),
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
  }

  Future<void> _finishAfterCreate(CatalogProduct created) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Producto creado · SKU ${created.sku}')),
    );
    final inv = widget.inventoryApi;
    final prefs = widget.localPrefs;
    if (inv == null || prefs == null) {
      Navigator.of(context).pop(true);
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Cargar stock inicial?'),
        content: Text(
          'Podés registrar ahora la cantidad en depósito para «${created.name}». '
          'Será un ajuste de entrada (IN_ADJUST) con motivo de inventario inicial. '
          'También podés hacerlo después en Inventario → Stock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cargar stock inicial'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (go == true) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (ctx) => InventoryAdjustmentScreen(
            storeId: widget.storeId,
            inventoryApi: inv,
            localPrefs: prefs,
            productId: created.id,
            productLabel: created.name,
            suggestedReason: 'Inventario inicial',
          ),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
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
                  ? 'Obligatorio al guardar. Independiente del código de barras salvo que uses el botón de abajo.'
                  : 'Opcional al crear: vacío → el servidor asigna SKU-000001, … No se copia del barras solo; usá «Usar código de barras como SKU» si querés el mismo valor.',
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
              hintText: 'Lo que escaneás en caja; no es lo mismo que el SKU salvo que elijas igualarlo',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear',
                onPressed: _loading ? null : _scanBarcodeField,
              ),
            ),
            keyboardType: TextInputType.text,
            enabled: !_loading,
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _loading ? null : _copyBarcodeToSku,
              icon: const Icon(Icons.link, size: 20),
              label: const Text('Usar código de barras como SKU'),
            ),
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
                  decoration: const InputDecoration(
                    labelText: 'Precio lista',
                    border: OutlineInputBorder(),
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
