import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/models/catalog_product.dart';

const _currencies = ['USD', 'VES', 'EUR'];
final _decimal = RegExp(r'^\d+(\.\d+)?$');

/// B5 — `POST /products` o `PATCH /products/:id`.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
    this.existing,
  });

  final String storeId;
  final ProductsApi productsApi;
  final CatalogProduct? existing;

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

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
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
    }
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
    final sku = _sku.text.trim();
    final name = _name.text.trim();
    final barcode = _barcode.text.trim();
    final price = _price.text.trim();
    final cost = _cost.text.trim();

    if (sku.isEmpty || name.isEmpty) {
      setState(() => _error = 'SKU y nombre son obligatorios.');
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

    final product = CatalogProduct(
      id: widget.existing?.id ?? '',
      sku: sku,
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
        await widget.productsApi.createProduct(
          widget.storeId,
          product.toCreateBody(),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isEdit ? 'Producto actualizado' : 'Producto creado'),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      var msg = e.userMessage;
      if (e.requestId != null) msg = '$msg\n(requestId: ${e.requestId})';
      setState(() => _error = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
            decoration: const InputDecoration(
              labelText: 'SKU',
              border: OutlineInputBorder(),
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
          TextField(
            controller: _barcode,
            decoration: const InputDecoration(
              labelText: 'Código de barras',
              hintText: 'Para escanear en el POS (Sprint 2)',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.text,
            enabled: !_loading,
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
