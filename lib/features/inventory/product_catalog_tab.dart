import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/uploads_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/network/product_image_url.dart';
import '../../core/catalog/pending_catalog_mutation_entry.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/catalog_product.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/text/search_text_match.dart';
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
    required this.localPrefs,
    this.uploadsApi,
    this.shellOnline = true,
    this.onLoadedCount,
  });

  final String storeId;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;
  final StoresApi storesApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final LocalPrefs localPrefs;
  final UploadsApi? uploadsApi;
  final bool shellOnline;
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
  void didUpdateWidget(covariant ProductCatalogTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) {
      setState(() {
        _all = [];
        _loading = true;
        _error = null;
      });
      unawaited(_load());
    }
    if (!oldWidget.shellOnline && widget.shellOnline) {
      unawaited(_load());
    }
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
    if (!widget.shellOnline) {
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      if (!mounted) return;
      setState(() {
        _all = cached;
        _error = cached.isEmpty
            ? 'Sin catálogo en caché. Conectate para sincronizar.'
            : null;
        _loading = false;
      });
      widget.onLoadedCount?.call(_all.length);
      return;
    }
    try {
      final list = await widget.productsApi.listProducts(widget.storeId);
      if (!mounted) return;
      await widget.localPrefs.saveCatalogProductsCache(list);
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
      widget.onLoadedCount?.call(_all.length);
    } on ApiError catch (e) {
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      if (!mounted) return;
      final msg = e.userMessageForSupport;
      setState(() {
        _all = cached;
        _error = cached.isEmpty ? msg : null;
        _loading = false;
      });
      widget.onLoadedCount?.call(_all.length);
    } catch (e) {
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      if (!mounted) return;
      setState(() {
        _all = cached;
        _error = cached.isEmpty
            ? 'No se pudo cargar el catálogo. Verificá la conexión.'
            : null;
        _loading = false;
      });
      widget.onLoadedCount?.call(_all.length);
    }
  }

  List<CatalogProduct> get _filtered {
    final q = _searchController.text.trim();
    if (q.isEmpty) return _all;
    return _all.where((p) {
      return searchTextMatchesAnyField(q, [p.name, p.sku, p.barcode]);
    }).toList();
  }

  Future<void> _openForm({CatalogProduct? existing}) async {
    if (!widget.shellOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión: no se pueden crear ni editar productos. '
            'Solo lectura desde cache.',
          ),
        ),
      );
      return;
    }
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (ctx) => ProductFormScreen(
          storeId: widget.storeId,
          productsApi: widget.productsApi,
          suppliersApi: widget.suppliersApi,
          storesApi: widget.storesApi,
          catalogInvalidationBus: widget.catalogInvalidationBus,
          localPrefs: widget.localPrefs,
          uploadsApi: widget.uploadsApi,
          shellOnline: widget.shellOnline,
          existing: existing,
        ),
      ),
    );
    if (mounted) await _load();
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
    setState(() => _searchController.text = code.trim());
  }

  Future<void> _confirmDeactivate(CatalogProduct p) async {
    if (!widget.shellOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin conexión: no se puede desactivar productos.'),
        ),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          '¿Desactivar "${p.name}"?\n\n'
          'No se borra del historial de ventas; deja de aparecer en catálogo activo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.productsApi.deactivateProduct(widget.storeId, p.id);
      if (!mounted) return;
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      cached.removeWhere((x) => x.id == p.id);
      if (!mounted) return;
      await widget.localPrefs.saveCatalogProductsCache(cached);
      if (!mounted) return;
      widget.catalogInvalidationBus.invalidateFromLocalMutation(
        productIds: {p.id},
      );
      setState(() => _all = cached);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto eliminado del catálogo activo')),
      );
      unawaited(_load());
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.isLikelyTransportFailure) {
        final pending = await widget.localPrefs.loadPendingCatalogMutations();
        pending.add(
          PendingCatalogMutationEntry(
            opId: ClientMutationId.newId(),
            storeId: widget.storeId,
            type: PendingCatalogMutationEntry.typeDeactivate,
            createdAtIso: DateTime.now().toUtc().toIso8601String(),
            productId: p.id,
          ),
        );
        await widget.localPrefs.savePendingCatalogMutations(pending);
        final cached = await widget.localPrefs.loadCatalogProductsCache();
        cached.removeWhere((x) => x.id == p.id);
        if (!mounted) return;
        await widget.localPrefs.saveCatalogProductsCache(cached);
        if (!mounted) return;
        widget.catalogInvalidationBus.invalidateFromLocalMutation(
          productIds: {p.id},
        );
        setState(() => _all = cached);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión: eliminación en cola para sincronizar.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessageForSupport)));
      }
    }
  }

  String? _resolvedImageUrl(String? raw) => resolveProductImageUrl(raw);

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
              child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'fab_inventory_product_catalog',
            onPressed: (!widget.shellOnline || _loading)
                ? null
                : () => _openForm(),
            icon: const Icon(Icons.add),
            label: Text(
              widget.shellOnline ? 'Nuevo producto' : 'Online para crear',
            ),
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
                  ? (widget.shellOnline
                        ? 'No hay productos activos. Usá el botón + para crear uno.'
                        : 'No hay productos en cache. Conectate para sincronizar el catálogo.')
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
        final bc = p.barcode != null && p.barcode!.isNotEmpty
            ? ' · ${p.barcode}'
            : '';
        final subChildren = <Widget>[
          Text('SKU ${p.sku}$bc', style: Theme.of(context).textTheme.bodySmall),
          Text(
            'Lista ${p.price} ${p.currency}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ];
        final sugTrim = p.suggestedPrice?.trim();
        if (sugTrim != null && sugTrim.isNotEmpty) {
          final em = p.effectiveMarginPercent?.trim();
          final mPart = (em != null && em.isNotEmpty)
              ? ' (margen efectivo $em%)'
              : '';
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
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 44,
              height: 44,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: () {
                final img = _resolvedImageUrl(p.imageUrl);
                if (img == null) {
                  return const Icon(Icons.inventory_2_outlined, size: 20);
                }
                return Image.network(
                  img,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image_outlined, size: 20),
                );
              }(),
            ),
          ),
          title: Text(p.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: subChildren,
          ),
          isThreeLine: subChildren.length >= 2,
          onTap: widget.shellOnline
              ? () => unawaited(_openForm(existing: p))
              : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Sin conexión: catálogo en solo lectura.',
                      ),
                    ),
                  );
                },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: widget.shellOnline ? 'Editar' : 'Online para editar',
                visualDensity: VisualDensity.compact,
                onPressed: widget.shellOnline
                    ? () => unawaited(_openForm(existing: p))
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: widget.shellOnline
                    ? 'Eliminar del catálogo'
                    : 'Online para eliminar',
                visualDensity: VisualDensity.compact,
                onPressed: widget.shellOnline
                    ? () => unawaited(_confirmDeactivate(p))
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
