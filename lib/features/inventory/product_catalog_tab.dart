import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/models/catalog_product.dart';
import '../sale/barcode_scanner_screen.dart';
import 'product_form_screen.dart';

/// B4 + acciones B5/B6 — catálogo de productos activos.
class ProductCatalogTab extends StatefulWidget {
  const ProductCatalogTab({
    super.key,
    required this.storeId,
    required this.productsApi,
    required this.suppliersApi,
    required this.storesApi,
    required this.catalogInvalidationBus,
    this.onLoadedCount,
  });

  final String storeId;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;
  final StoresApi storesApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final ValueChanged<int>? onLoadedCount;

  @override
  State<ProductCatalogTab> createState() => _ProductCatalogTabState();
}

class _ProductCatalogTabState extends State<ProductCatalogTab> {
  final _searchController = TextEditingController();
  List<CatalogProduct> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    widget.catalogInvalidationBus.addListener(_onCatalogInvalidated);
    _load();
  }

  @override
  void dispose() {
    widget.catalogInvalidationBus.removeListener(_onCatalogInvalidated);
    _searchController.dispose();
    super.dispose();
  }

  void _onCatalogInvalidated() {
    if (mounted) unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.productsApi.listProducts(widget.storeId);
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
      widget.onLoadedCount?.call(_all.length);
    } on ApiError catch (e) {
      if (!mounted) return;
      final msg = e.userMessageForSupport;
      setState(() {
        _all = [];
        _error = msg;
        _loading = false;
      });
      widget.onLoadedCount?.call(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _error = e.toString();
        _loading = false;
      });
      widget.onLoadedCount?.call(0);
    }
  }

  List<CatalogProduct> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<void> _openForm({
    CatalogProduct? existing,
    String? prefilledBarcode,
  }) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => ProductFormScreen(
          storeId: widget.storeId,
          productsApi: widget.productsApi,
          suppliersApi: widget.suppliersApi,
          storesApi: widget.storesApi,
          catalogInvalidationBus: widget.catalogInvalidationBus,
          existing: existing,
          initialBarcode:
              existing == null ? prefilledBarcode : null,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  bool _anyProductExactBarcode(String raw) {
    final c = raw.trim().toLowerCase();
    if (c.isEmpty) return false;
    for (final p in _all) {
      final b = p.barcode?.trim().toLowerCase();
      if (b != null && b.isNotEmpty && b == c) return true;
    }
    return false;
  }

  Future<void> _onScanPressed() async {
    if (_loading) return;
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
    setState(() => _searchController.text = code);
    if (!_anyProductExactBarcode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No hay producto activo con este código de barras.',
          ),
          action: SnackBarAction(
            label: 'Crear producto',
            onPressed: () => _openForm(prefilledBarcode: code),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeactivate(CatalogProduct p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desactivar producto'),
        content: Text('¿Desactivar "${p.name}"? No se borra del historial.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.productsApi.deactivateProduct(widget.storeId, p.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto desactivado')),
      );
      await _load();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessageForSupport)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar producto, SKU o código de barras',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    tooltip: 'Escanear',
                    onPressed: _loading ? null : _onScanPressed,
                  ),
                ),
                autocorrect: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
              child: Text(
                'Alta de producto sin proveedor: el API no lo exige. Los proveedores se usan en compras (más adelante).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _buildBody(),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _loading ? null : () => _openForm(),
            icon: const Icon(Icons.add),
            label: const Text('Nuevo producto'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 100),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.1),
          Center(
            child: Text(
              _all.isEmpty
                  ? 'No hay productos activos. Usá el botón + para crear uno.'
                  : 'Sin resultados.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final p = items[i];
        final bc =
            p.barcode != null && p.barcode!.isNotEmpty ? ' · ${p.barcode}' : '';
        final subChildren = <Widget>[
          Text(
            'SKU ${p.sku}$bc',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'Lista ${p.price} ${p.currency}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ];
        final sugTrim = p.suggestedPrice?.trim();
        if (sugTrim != null && sugTrim.isNotEmpty) {
          final em = p.effectiveMarginPercent?.trim();
          final mPart =
              (em != null && em.isNotEmpty) ? ' (margen efectivo $em%)' : '';
          subChildren.add(
            Text(
              'Sugerido API $sugTrim ${p.currency}$mPart',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        if (p.pricingMode == 'MANUAL_PRICE') {
          subChildren.add(
            Text(
              'Precio manual: una compra no cambia la lista en el servidor.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        return ListTile(
          title: Text(p.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: subChildren,
          ),
          isThreeLine: subChildren.length >= 2,
          onTap: () => _openForm(existing: p),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') _openForm(existing: p);
              if (v == 'deactivate') _confirmDeactivate(p);
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              const PopupMenuItem(
                value: 'deactivate',
                child: Text('Desactivar'),
              ),
            ],
          ),
        );
      },
    );
  }
}
