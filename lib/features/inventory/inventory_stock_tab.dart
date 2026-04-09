import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/uploads_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/inventory_line.dart';
import '../sale/barcode_scanner_screen.dart';
import 'inventory_product_detail_screen.dart';
import 'product_form_screen.dart';

/// Filtro por cantidad / mínimo (`FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md` §2).
enum _StockListFilter {
  all,
  outOfStock,
  belowMin,
}

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

  Future<void> _loadStoreMargin() async {
    try {
      final bs =
          await widget.storesApi.getBusinessSettings(widget.storeId);
      if (!mounted) return;
      final m = bs.defaultMarginPercent?.trim();
      setState(() {
        _storeDefaultMarginPercent =
            (m == null || m.isEmpty) ? null : m;
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
    try {
      final list = await widget.inventoryApi.listInventory(widget.storeId);
      await widget.localPrefs.saveInventoryCache(widget.storeId, list);
      List<CatalogProduct> catalog = const [];
      try {
        final raw = await widget.productsApi.listProducts(
          widget.storeId,
          includeInactive: false,
        );
        await widget.localPrefs.saveCatalogProductsCache(raw);
        catalog = raw.where((p) => p.active).toList();
      } catch (_) {
        final cachedCatalog = await widget.localPrefs.loadCatalogProductsCache();
        catalog = cachedCatalog.where((p) => p.active).toList();
      }
      final inInventory = list.map((l) => l.productId).toSet();
      final synthetic = <InventoryLine>[];
      for (final p in catalog) {
        if (!inInventory.contains(p.id)) {
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
      final merged = [...list, ...synthetic]..sort(
            (a, b) => a.displayName
                .toLowerCase()
                .compareTo(b.displayName.toLowerCase()),
          );
      if (!mounted) return;
      setState(() {
        _all = merged;
        _loading = false;
        _usingCachedData = false;
      });
      widget.onLoadedCount?.call(_all.length);
    } on ApiError catch (e) {
      final cachedInv = await widget.localPrefs.loadInventoryCache(widget.storeId);
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
      final cachedInv = await widget.localPrefs.loadInventoryCache(widget.storeId);
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

  List<InventoryLine> _mergeInventoryWithCatalog(
    List<InventoryLine> list,
    List<CatalogProduct> catalogRaw,
  ) {
    final catalog = catalogRaw.where((p) => p.active).toList();
    final inInventory = list.map((l) => l.productId).toSet();
    final synthetic = <InventoryLine>[];
    for (final p in catalog) {
      if (!inInventory.contains(p.id)) {
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
    return [...list, ...synthetic]
      ..sort(
        (a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()),
      );
  }

  bool _anyLineExactBarcode(String raw) {
    final c = raw.trim().toLowerCase();
    if (c.isEmpty) return false;
    for (final line in _all) {
      final b = line.product?.barcode?.trim().toLowerCase();
      if (b != null && b.isNotEmpty && b == c) return true;
    }
    return false;
  }

  Future<void> _openNewProductWithBarcode(String code) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => ProductFormScreen(
          storeId: widget.storeId,
          productsApi: widget.productsApi,
          suppliersApi: widget.suppliersApi,
          localPrefs: widget.localPrefs,
          storesApi: widget.storesApi,
          catalogInvalidationBus: widget.catalogInvalidationBus,
          uploadsApi: widget.uploadsApi,
          initialBarcode: code,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
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
    if (!_anyLineExactBarcode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No hay producto en stock con este código de barras.',
          ),
          action: SnackBarAction(
            label: 'Crear producto',
            onPressed: () => _openNewProductWithBarcode(code),
          ),
        ),
      );
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
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(),
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
        final barcodeSuffix = line.product?.barcode != null &&
                line.product!.barcode!.isNotEmpty
            ? ' · ${line.product!.barcode}'
            : '';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: (!synth && (line.isOutOfStock || line.isBelowMinimumStock))
              ? Icon(
                  line.isOutOfStock ? Icons.inventory_2_outlined : Icons.warning_amber_outlined,
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
          onTap: () {
            Navigator.of(context).push<void>(
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
                ),
              ),
            );
          },
          trailing: Column(
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
        );
      },
    );
  }
}
