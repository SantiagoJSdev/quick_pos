import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/uploads_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/catalog/pending_catalog_mutation_entry.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/inventory_line.dart';
import '../sale/barcode_scanner_screen.dart';
import 'inventory_product_detail_screen.dart';
import 'product_form_screen.dart';

/// Filtro por cantidad / mínimo (`FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md` §2).
enum _StockListFilter { all, outOfStock, belowMin }

/// B1 — contenido de **Stock** (sin `Scaffold`; va dentro de [InventoryModuleScreen]).
class InventoryStockTab extends StatefulWidget {
  const InventoryStockTab({
    super.key,
    required this.storeId,
    required this.inventoryApi,
    required this.productsApi,
    required this.suppliersApi,
    required this.storesApi,
    this.uploadsApi,
    required this.localPrefs,
    required this.catalogInvalidationBus,
    this.shellOnline = true,
    this.shellInventoryTabActive = true,
    this.onLoadedCount,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;
  final StoresApi storesApi;
  final UploadsApi? uploadsApi;
  final LocalPrefs localPrefs;
  final CatalogInvalidationBus catalogInvalidationBus;

  /// Desde [MainShell]: evita llamadas HTTP que bloquean hasta timeout.
  final bool shellOnline;

  /// Cuando el usuario vuelve a la pestaña Inventario del shell, se vuelve a pedir stock al API.
  final bool shellInventoryTabActive;

  /// Total de líneas tras cada carga (para contador en el módulo).
  final ValueChanged<int>? onLoadedCount;

  @override
  State<InventoryStockTab> createState() => _InventoryStockTabState();
}

class _InventoryStockTabState extends State<InventoryStockTab> {
  final _searchController = TextEditingController();
  List<InventoryLine> _all = [];
  bool _loading = true;
  String? _error;
  _StockListFilter _stockFilter = _StockListFilter.all;
  String? _storeDefaultMarginPercent;
  bool _usingCachedData = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    widget.catalogInvalidationBus.addListener(_onCatalogInvalidated);
    unawaited(_loadStoreMargin());
    _load();
  }

  @override
  void didUpdateWidget(covariant InventoryStockTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storeId != widget.storeId) {
      setState(() {
        _all = [];
        _loading = true;
        _error = null;
        _usingCachedData = false;
      });
      unawaited(_load());
      unawaited(_loadStoreMargin());
    }
    if (!oldWidget.shellOnline && widget.shellOnline) {
      unawaited(_load());
      unawaited(_loadStoreMargin());
    }
    if (!oldWidget.shellInventoryTabActive && widget.shellInventoryTabActive) {
      unawaited(_load());
      unawaited(_loadStoreMargin());
    }
  }

  Future<void> _loadStoreMargin() async {
    if (!widget.shellOnline) return;
    try {
      final bs = await widget.storesApi.getBusinessSettings(widget.storeId);
      if (!mounted) return;
      final m = bs.defaultMarginPercent?.trim();
      setState(() {
        _storeDefaultMarginPercent = (m == null || m.isEmpty) ? null : m;
      });
    } catch (_) {
      /* opcional: sin margen en settings */
    }
  }

  @override
  void dispose() {
    widget.catalogInvalidationBus.removeListener(_onCatalogInvalidated);
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCatalogInvalidated() {
    if (mounted) unawaited(_load());
  }

  void _onSearchChanged() => setState(() {});

  List<InventoryLine> get _stockFiltered {
    switch (_stockFilter) {
      case _StockListFilter.all:
        return _all;
      case _StockListFilter.outOfStock:
        return _all.where((l) => l.isOutOfStock).toList();
      case _StockListFilter.belowMin:
        return _all.where((l) => l.isBelowMinimumStock).toList();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.shellOnline) {
      final cachedInv = await widget.localPrefs.loadInventoryCache(
        widget.storeId,
      );
      final cachedCatalog = await widget.localPrefs.loadCatalogProductsCache();
      final merged = _mergeInventoryWithCatalog(cachedInv, cachedCatalog);
      if (!mounted) return;
      setState(() {
        _all = merged;
        _error = merged.isEmpty
            ? 'Sin inventario en caché. Conectate para sincronizar.'
            : null;
        _loading = false;
        _usingCachedData = merged.isNotEmpty;
      });
      widget.onLoadedCount?.call(_all.length);
      return;
    }
    try {
      final list = await widget.inventoryApi.listInventory(widget.storeId);
      if (!mounted) return;
      await widget.localPrefs.saveInventoryCache(widget.storeId, list);
      List<CatalogProduct> catalogRaw = const [];
      try {
        final raw = await widget.productsApi.listProducts(
          widget.storeId,
          includeInactive: false,
        );
        if (!mounted) return;
        await widget.localPrefs.saveCatalogProductsCache(raw);
        catalogRaw = raw;
      } catch (_) {
        catalogRaw = await widget.localPrefs.loadCatalogProductsCache();
      }
      final merged = _mergeInventoryWithCatalog(list, catalogRaw);
      if (!mounted) return;
      setState(() {
        _all = merged;
        _loading = false;
        _usingCachedData = false;
      });
      widget.onLoadedCount?.call(_all.length);
    } on ApiError catch (e) {
      final cachedInv = await widget.localPrefs.loadInventoryCache(
        widget.storeId,
      );
      final cachedCatalog = await widget.localPrefs.loadCatalogProductsCache();
      final merged = _mergeInventoryWithCatalog(cachedInv, cachedCatalog);
      if (!mounted) return;
      if (merged.isNotEmpty) {
        setState(() {
          _all = merged;
          _error = null;
          _loading = false;
          _usingCachedData = true;
        });
        widget.onLoadedCount?.call(_all.length);
      } else {
        final msg = e.userMessageForSupport;
        setState(() {
          _all = [];
          _error = msg;
          _loading = false;
        });
        widget.onLoadedCount?.call(0);
      }
    } catch (e) {
      final cachedInv = await widget.localPrefs.loadInventoryCache(
        widget.storeId,
      );
      final cachedCatalog = await widget.localPrefs.loadCatalogProductsCache();
      final merged = _mergeInventoryWithCatalog(cachedInv, cachedCatalog);
      if (!mounted) return;
      if (merged.isNotEmpty) {
        setState(() {
          _all = merged;
          _error = null;
          _loading = false;
          _usingCachedData = true;
        });
        widget.onLoadedCount?.call(_all.length);
      } else {
        setState(() {
          _all = [];
          _error = e.toString();
          _loading = false;
        });
        widget.onLoadedCount?.call(0);
      }
    }
  }

  /// `productId` de la línea o, si falta, el id embebido en [InventoryLine.product].
  String _lineProductId(InventoryLine l) {
    final fromField = l.productId.trim();
    if (fromField.isNotEmpty) return fromField;
    return (l.product?.id ?? '').trim();
  }

  /// Solo líneas cuyo producto sigue en catálogo **activo** más filas sintéticas
  /// (catálogo sin movimientos en inventario). El API de inventario puede seguir
  /// devolviendo stock de productos dados de baja en catálogo; no los listamos acá.
  ///
  /// Enriquece `product.barcode`/`sku`/`name` desde el catálogo porque
  /// `GET /inventory` a menudo no trae el código de barras embebido.
  List<InventoryLine> _mergeInventoryWithCatalog(
    List<InventoryLine> list,
    List<CatalogProduct> catalogRaw,
  ) {
    final catalog = catalogRaw.where((p) => p.active).toList();
    final byId = <String, CatalogProduct>{
      for (final p in catalog)
        if (p.id.trim().isNotEmpty) p.id.trim(): p,
    };
    final activeIds = byId.keys.toSet();
    final filteredList = <InventoryLine>[];
    for (final l in list) {
      final pid = _lineProductId(l);
      if (pid.isEmpty || !activeIds.contains(pid)) continue;
      filteredList.add(_enrichLineFromCatalog(l, byId[pid]!));
    }
    final inInventory = filteredList
        .map(_lineProductId)
        .where((id) => id.isNotEmpty)
        .toSet();
    final synthetic = <InventoryLine>[];
    for (final p in catalog) {
      final pid = p.id.trim();
      if (pid.isEmpty) continue;
      if (!inInventory.contains(pid)) {
        synthetic.add(
          InventoryLine.syntheticZeroStock(
            productId: p.id,
            sku: p.sku,
            name: p.name,
            barcode: p.barcode,
          ),
        );
      }
    }
    return [...filteredList, ...synthetic]..sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
  }

  InventoryLine _enrichLineFromCatalog(InventoryLine line, CatalogProduct p) {
    final existing = line.product;
    final barcode = (p.barcode?.trim().isNotEmpty == true)
        ? p.barcode
        : existing?.barcode;
    final sku = p.sku.trim().isNotEmpty ? p.sku : existing?.sku;
    final name = p.name.trim().isNotEmpty ? p.name : existing?.name;
    return InventoryLine(
      id: line.id,
      productId: line.productId.trim().isNotEmpty ? line.productId : p.id,
      quantity: line.quantity,
      reserved: line.reserved,
      minStock: line.minStock,
      averageUnitCostFunctional: line.averageUnitCostFunctional,
      totalCostFunctional: line.totalCostFunctional,
      product: InventoryProductSummary(
        id: (existing?.id.trim().isNotEmpty == true) ? existing!.id : p.id,
        sku: sku,
        name: name,
        barcode: barcode,
      ),
    );
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

  Future<void> _openEditForLine(InventoryLine line) async {
    if (!widget.shellOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sin conexión: no se puede editar productos. '
            'Solo lectura desde cache.',
          ),
        ),
      );
      return;
    }
    final pid = line.productId.trim().isNotEmpty
        ? line.productId.trim()
        : line.product?.id.trim() ?? '';
    if (pid.isEmpty) return;
    CatalogProduct? p;
    if (widget.shellOnline) {
      p = await widget.productsApi.getProduct(widget.storeId, pid);
    }
    if (p == null) {
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      for (final x in cached) {
        if (x.id == pid) {
          p = x;
          break;
        }
      }
    }
    if (!mounted) return;
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se encontró la ficha del producto. '
            'Conectate o abrilo desde la pestaña Catálogo.',
          ),
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (ctx) => ProductFormScreen(
          storeId: widget.storeId,
          productsApi: widget.productsApi,
          suppliersApi: widget.suppliersApi,
          localPrefs: widget.localPrefs,
          storesApi: widget.storesApi,
          catalogInvalidationBus: widget.catalogInvalidationBus,
          uploadsApi: widget.uploadsApi,
          shellOnline: widget.shellOnline,
          existing: p,
        ),
      ),
    );
    if (result != null && mounted) await _load();
  }

  Future<void> _confirmDeactivateLine(InventoryLine line) async {
    if (!widget.shellOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin conexión: no se puede desactivar productos.'),
        ),
      );
      return;
    }
    final name = line.displayName;
    final pid = line.productId.trim().isNotEmpty
        ? line.productId.trim()
        : line.product?.id.trim() ?? '';
    if (pid.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          '¿Desactivar "$name"?\n\n'
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
      await widget.productsApi.deactivateProduct(widget.storeId, pid);
      if (!mounted) return;
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      cached.removeWhere((x) => x.id == pid);
      if (!mounted) return;
      await widget.localPrefs.saveCatalogProductsCache(cached);
      if (!mounted) return;
      widget.catalogInvalidationBus.invalidateFromLocalMutation(
        productIds: {pid},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Producto eliminado del catálogo activo')),
      );
      if (mounted) await _load();
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
            productId: pid,
          ),
        );
        await widget.localPrefs.savePendingCatalogMutations(pending);
        final cached = await widget.localPrefs.loadCatalogProductsCache();
        cached.removeWhere((x) => x.id == pid);
        if (!mounted) return;
        await widget.localPrefs.saveCatalogProductsCache(cached);
        if (!mounted) return;
        widget.catalogInvalidationBus.invalidateFromLocalMutation(
          productIds: {pid},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión: eliminación en cola para sincronizar.',
            ),
          ),
        );
        if (mounted) await _load();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.userMessageForSupport)));
      }
    }
  }

  List<InventoryLine> get _filtered {
    final base = _stockFiltered;
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((line) {
      final name = line.product?.name?.toLowerCase() ?? '';
      final sku = line.product?.sku?.toLowerCase() ?? '';
      final bc = line.product?.barcode?.toLowerCase() ?? '';
      return name.contains(q) || sku.contains(q) || bc.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, SKU o código de barras',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear',
                onPressed: _loading ? null : _onScanPressed,
              ),
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Tooltip(
                  message: 'Mostrar todas las líneas (según búsqueda).',
                  child: FilterChip(
                    label: const Text('Todos'),
                    selected: _stockFilter == _StockListFilter.all,
                    onSelected: _loading
                        ? null
                        : (v) => setState(() {
                            if (v) _stockFilter = _StockListFilter.all;
                          }),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'Cantidad en cero o menos: ya no hay disponible para vender.',
                  child: FilterChip(
                    label: const Text('Sin stock'),
                    selected: _stockFilter == _StockListFilter.outOfStock,
                    onSelected: _loading
                        ? null
                        : (v) => setState(() {
                            _stockFilter = v
                                ? _StockListFilter.outOfStock
                                : _StockListFilter.all;
                          }),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message:
                      'Siguen teniendo stock pero ya están en el piso o por debajo '
                      'del mínimo que marca el servidor (minStock): conviene reponer '
                      'antes de quedarse en cero.',
                  child: FilterChip(
                    label: const Text('Bajo mínimo'),
                    selected: _stockFilter == _StockListFilter.belowMin,
                    onSelected: _loading
                        ? null
                        : (v) => setState(() {
                            _stockFilter = v
                                ? _StockListFilter.belowMin
                                : _StockListFilter.all;
                          }),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Text(
            'Sin stock = nada disponible (cantidad ≤ 0). '
            'Bajo mínimo = todavía hay unidades pero están por acabarse: la cantidad '
            'es mayor que cero y no supera el piso minStock que envía el API (reponer pronto). '
            'Incluye productos de catálogo sin movimientos (0). Buscá o escaneá con el ícono.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_usingCachedData)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              'Mostrando inventario cacheado (modo offline).',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        Expanded(
          child: RefreshIndicator(onRefresh: _load, child: _buildBody()),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
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
          SizedBox(height: MediaQuery.of(context).size.height * 0.12),
          Center(
            child: Text(
              _all.isEmpty
                  ? 'No hay productos en catálogo ni líneas de inventario.\n\n'
                        'Creá productos en la pestaña Catálogo (arriba); '
                        'aparecerán acá con 0 hasta la primera compra o ajuste de stock.'
                  : _searchController.text.trim().isNotEmpty
                  ? 'Ningún resultado para la búsqueda y el filtro actual.'
                  : _stockFilter != _StockListFilter.all
                  ? 'Ningún producto cumple este filtro de stock.\n\n'
                        '“Bajo mínimo” solo aplica si el API envía minStock > 0.'
                  : 'Ningún resultado.',
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
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final line = items[i];
        final synth = line.isSyntheticInventoryRow;
        final min = line.minStock?.trim();
        final minSuffix = (min != null && min.isNotEmpty) ? ' · mín. $min' : '';
        final barcodeSuffix =
            line.product?.barcode != null && line.product!.barcode!.isNotEmpty
            ? ' · ${line.product!.barcode}'
            : '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: (!synth && (line.isOutOfStock || line.isBelowMinimumStock))
              ? Icon(
                  line.isOutOfStock
                      ? Icons.inventory_2_outlined
                      : Icons.warning_amber_outlined,
                  color: line.isOutOfStock
                      ? Theme.of(context).colorScheme.outline
                      : Theme.of(context).colorScheme.tertiary,
                )
              : null,
          title: Text(line.displayName),
          subtitle: Text(
            synth
                ? 'Sin movimientos de inventario · SKU: ${line.displaySku}$barcodeSuffix$minSuffix'
                : 'SKU: ${line.displaySku}$barcodeSuffix$minSuffix',
          ),
          onTap: () async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (ctx) => InventoryProductDetailScreen(
                  storeId: widget.storeId,
                  inventoryApi: widget.inventoryApi,
                  productsApi: widget.productsApi,
                  suppliersApi: widget.suppliersApi,
                  localPrefs: widget.localPrefs,
                  catalogInvalidationBus: widget.catalogInvalidationBus,
                  initialLine: line,
                  storeDefaultMarginPercent: _storeDefaultMarginPercent,
                  storesApi: widget.storesApi,
                  uploadsApi: widget.uploadsApi,
                  shellOnline: widget.shellOnline,
                ),
              ),
            );
            if (mounted) await _load();
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    line.quantity,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    synth ? 'catálogo' : 'disp.',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: widget.shellOnline
                    ? 'Editar producto'
                    : 'Online para editar',
                visualDensity: VisualDensity.compact,
                onPressed: widget.shellOnline
                    ? () => unawaited(_openEditForLine(line))
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: widget.shellOnline
                    ? 'Eliminar del catálogo'
                    : 'Online para eliminar',
                visualDensity: VisualDensity.compact,
                onPressed: widget.shellOnline
                    ? () => unawaited(_confirmDeactivateLine(line))
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
