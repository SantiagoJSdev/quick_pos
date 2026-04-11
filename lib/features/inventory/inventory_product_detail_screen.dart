import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/inventory_line.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/api/uploads_api.dart';
import '../../core/network/product_image_url.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/models/stock_movement.dart';
import '../../core/pos/post_purchase_price_hint.dart';
import 'inventory_adjustment_screen.dart';
import 'product_form_screen.dart';

/// B2 — detalle de stock + movimientos recientes.
class InventoryProductDetailScreen extends StatefulWidget {
  const InventoryProductDetailScreen({
    super.key,
    required this.storeId,
    required this.inventoryApi,
    required this.productsApi,
    required this.suppliersApi,
    this.storesApi,
    required this.localPrefs,
    required this.catalogInvalidationBus,
    required this.initialLine,
    this.storeDefaultMarginPercent,
    this.uploadsApi,
    this.shellOnline = true,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;
  final StoresApi? storesApi;
  final LocalPrefs localPrefs;
  final CatalogInvalidationBus catalogInvalidationBus;
  final InventoryLine initialLine;
  final UploadsApi? uploadsApi;

  /// Margen % de tienda si el producto usa `USE_STORE_DEFAULT` o aún no cargó la ficha.
  final String? storeDefaultMarginPercent;

  /// Desde [MainShell]: sin llamadas HTTP al abrir el detalle.
  final bool shellOnline;

  String get _productId {
    final fromLine = initialLine.productId.trim();
    if (fromLine.isNotEmpty) return fromLine;
    return initialLine.product?.id.trim() ?? '';
  }

  @override
  State<InventoryProductDetailScreen> createState() =>
      _InventoryProductDetailScreenState();
}

class _InventoryProductDetailScreenState
    extends State<InventoryProductDetailScreen> {
  InventoryLine? _line;
  CatalogProduct? _catalogProduct;
  List<StockMovement> _movements = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _line = widget.initialLine;
    widget.catalogInvalidationBus.addListener(_onCatalogInvalidated);
    _load();
  }

  @override
  void didUpdateWidget(covariant InventoryProductDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shellOnline && widget.shellOnline) {
      unawaited(_load());
    }
  }

  void _onCatalogInvalidated() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    widget.catalogInvalidationBus.removeListener(_onCatalogInvalidated);
    super.dispose();
  }

  Future<void> _load() async {
    final pid = widget._productId;
    if (pid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Falta productId en la línea de inventario.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    if (!widget.shellOnline) {
      final cachedProducts = await widget.localPrefs.loadCatalogProductsCache();
      CatalogProduct? cp;
      for (final p in cachedProducts) {
        if (p.id == pid) {
          cp = p;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _catalogProduct = cp;
        _line = widget.initialLine;
        _movements = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    try {
      final detailFuture = widget.inventoryApi.getInventoryLine(
        widget.storeId,
        pid,
      );
      final movFuture = widget.inventoryApi.listMovements(
        widget.storeId,
        productId: pid,
        limit: 100,
      );
      final productFuture = widget.productsApi.getProduct(widget.storeId, pid);
      final detail = await detailFuture;
      final mov = await movFuture;
      final product = await productFuture;
      if (!mounted) return;
      setState(() {
        _line = detail ?? widget.initialLine;
        _catalogProduct = product;
        _movements = mov;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessageForSupport;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openAdjustment(String productId, String label) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => InventoryAdjustmentScreen(
          storeId: widget.storeId,
          inventoryApi: widget.inventoryApi,
          localPrefs: widget.localPrefs,
          productId: productId,
          productLabel: label,
          catalogInvalidationBus: widget.catalogInvalidationBus,
        ),
      ),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _openEditProduct(CatalogProduct product) async {
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
          shellOnline: widget.shellOnline,
          existing: product,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  String _formatWhen(DateTime? t) {
    if (t == null) return '—';
    final l = t.toLocal();
    final d =
        '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
    final h =
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    return '$d $h';
  }

  String? _resolvedImageUrl(String? raw) => resolveProductImageUrl(raw);

  @override
  Widget build(BuildContext context) {
    final line = _line ?? widget.initialLine;
    final title = line.displayName;

    final pid = widget._productId;
    final cat = _catalogProduct;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (cat != null && !_loading && _error == null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar producto y margen',
              onPressed: () => _openEditProduct(cat),
            ),
          if (pid.isNotEmpty && !_loading && _error == null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Ajustar stock',
              onPressed: () => _openAdjustment(pid, line.displayName),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _error == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
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
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      if (cat == null && pid.isNotEmpty) ...[
                        Card(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'No se pudo cargar la ficha del producto. '
                              'Para margen individual y precio: pestaña Catálogo → editar.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (cat != null) ...[
                        if (_resolvedImageUrl(cat.imageUrl) != null) ...[
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Image.network(
                                    _resolvedImageUrl(cat.imageUrl)!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        Container(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      child: const Center(
                                        child: Icon(Icons.broken_image_outlined),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          'Precio y margen (catálogo)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _kv(
                                  'Precio lista',
                                  '${cat.price} ${cat.currency}',
                                ),
                                _kv('Costo ficha', '${cat.cost} ${cat.currency}'),
                                _kv(
                                  'Política de margen',
                                  PostPurchasePriceHint.pricingModeLabelEs(
                                    cat.pricingMode,
                                  ),
                                ),
                                if (cat.pricingMode == 'USE_PRODUCT_OVERRIDE' &&
                                    cat.marginPercentOverride != null &&
                                    cat.marginPercentOverride!.trim().isNotEmpty)
                                  _kv(
                                    'Margen propio %',
                                    cat.marginPercentOverride!.trim(),
                                  ),
                                if (cat.effectiveMarginPercent != null &&
                                    cat.effectiveMarginPercent!.trim().isNotEmpty)
                                  _kv(
                                    'Margen efectivo (API)',
                                    '${cat.effectiveMarginPercent!.trim()}%',
                                  ),
                                if (cat.suggestedPrice != null &&
                                    cat.suggestedPrice!.trim().isNotEmpty)
                                  _kv(
                                    'Precio sugerido (API, sobre costo ficha)',
                                    '${cat.suggestedPrice!.trim()} ${cat.currency}',
                                  ),
                                const SizedBox(height: 8),
                                FilledButton.tonalIcon(
                                  onPressed: () => _openEditProduct(cat),
                                  icon: const Icon(Icons.percent_outlined),
                                  label: const Text('Cambiar margen / precio'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text(
                        'Stock',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _kv('Disponible', line.quantity),
                              _kv('Reservado', line.reserved),
                              if (line.minStock != null &&
                                  line.minStock!.trim().isNotEmpty)
                                _kv('Stock mínimo', line.minStock!),
                              if (line.averageUnitCostFunctional != null &&
                                  line.averageUnitCostFunctional!.isNotEmpty)
                                _kv(
                                  'Costo medio (func.)',
                                  line.averageUnitCostFunctional!,
                                ),
                              if (line.totalCostFunctional != null &&
                                  line.totalCostFunctional!.isNotEmpty)
                                _kv(
                                  'Valor stock (func.)',
                                  line.totalCostFunctional!,
                                ),
                              _kv('SKU', line.displaySku),
                              if (line.product?.barcode != null &&
                                  line.product!.barcode!.isNotEmpty)
                                _kv('Código de barras', line.product!.barcode!),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        PostPurchasePriceHint.stockDetailPolicyLine,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.35,
                            ),
                      ),
                      Builder(
                        builder: (ctx) {
                          final avg = line.averageUnitCostFunctional?.trim();
                          if (avg == null || avg.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final p = _catalogProduct;
                          if (p?.pricingMode == 'MANUAL_PRICE') {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Precio manual: no aplica sugerencia por margen '
                                'sobre el costo medio de depósito.',
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(ctx)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      height: 1.35,
                                    ),
                              ),
                            );
                          }
                          final marginPct =
                              PostPurchasePriceHint
                                  .marginPercentForAverageCostSuggestion(
                            product: p,
                            storeDefaultMarginPercent:
                                widget.storeDefaultMarginPercent,
                          );
                          if (marginPct == null || marginPct.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          final localSug = PostPurchasePriceHint
                              .suggestedListFromAverageCostAndStoreMargin(
                            line.averageUnitCostFunctional,
                            marginPct,
                          );
                          if (localSug == null) {
                            return const SizedBox.shrink();
                          }
                          final src = p?.pricingMode == 'USE_PRODUCT_OVERRIDE'
                              ? 'margen propio del producto'
                              : 'margen de la tienda';
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Sugerido sobre costo medio ($src, $marginPct%): '
                              '$localSug (moneda funcional). '
                              '${PostPurchasePriceHint.catalogSuggestedUsesProductCost}',
                              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    height: 1.35,
                                  ),
                            ),
                          );
                        },
                      ),
                      if (pid.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: () => _openAdjustment(pid, line.displayName),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Ajustar stock'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Movimientos recientes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Últimos movimientos del producto (hasta 100).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      if (_movements.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Sin movimientos registrados.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        )
                      else
                        ..._movements.map(
                          (m) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(m.type),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatWhen(m.createdAt) +
                                        (m.reason != null &&
                                                m.reason!.isNotEmpty
                                            ? ' · ${m.reason}'
                                            : ''),
                                  ),
                                  if (m.referenceId != null &&
                                      m.referenceId!.isNotEmpty)
                                    Text(
                                      'Ref: ${m.referenceId}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  if (m.priceAtMoment != null &&
                                      m.priceAtMoment!.isNotEmpty)
                                    Text(
                                      'Precio (momento): ${m.priceAtMoment}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                m.quantity,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
