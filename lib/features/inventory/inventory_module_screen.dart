import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/uploads_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/widgets/quickmarket_branding.dart';
import '../sale/pos_sale_ui_tokens.dart';
import 'inventory_stock_tab.dart';
import 'product_catalog_tab.dart';

/// Pestaña **Inventario**: **Stock** (B1) y **Catálogo** (B4–B6) con [SegmentedButton].
///
/// Lectura offline desde cache; altas/ajustes/edición requieren [shellOnline].
class InventoryModuleScreen extends StatefulWidget {
  const InventoryModuleScreen({
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
    this.onRetryOnline,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;
  final StoresApi storesApi;
  final UploadsApi? uploadsApi;
  final LocalPrefs localPrefs;
  final CatalogInvalidationBus catalogInvalidationBus;

  /// Desde [MainShell]: mutaciones de inventario solo si online.
  final bool shellOnline;

  /// `true` cuando la pestaña principal del shell es Inventario.
  final bool shellInventoryTabActive;

  /// Probe + sync desde el shell (botón Reintentar del banner).
  final Future<void> Function()? onRetryOnline;

  @override
  State<InventoryModuleScreen> createState() => _InventoryModuleScreenState();
}

class _InventoryModuleScreenState extends State<InventoryModuleScreen> {
  int _tab = 0;
  int? _stockLineCount;
  int? _catalogProductCount;
  bool _retryBusy = false;

  String _countSuffix() {
    if (_tab == 0) {
      final n = _stockLineCount;
      if (n == null) return '';
      return ' · $n ${n == 1 ? 'línea' : 'líneas'}';
    }
    final n = _catalogProductCount;
    if (n == null) return '';
    return ' · $n ${n == 1 ? 'producto' : 'productos'}';
  }

  Future<void> _onRetryPressed() async {
    final fn = widget.onRetryOnline;
    if (fn == null || _retryBusy) return;
    setState(() => _retryBusy = true);
    try {
      await fn();
    } finally {
      if (mounted) setState(() => _retryBusy = false);
    }
  }

  Widget _offlineReadOnlyBanner(BuildContext context) {
    return Material(
      color: const Color(0xFF3A2F1A),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 20,
              color: Colors.orangeAccent,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sin conexión: solo lectura (cache). '
                'Para agregar o ajustar stock necesitás estar online.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.text,
                  height: 1.3,
                ),
              ),
            ),
            TextButton(
              onPressed: _retryBusy ? null : () => unawaited(_onRetryPressed()),
              child: _retryBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = widget.shellOnline;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, right: 10),
              child: QuickMarketLogoMark(size: 32, borderRadius: 10),
            ),
            Text(
              'Inventario',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: PosSaleUi.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!online) _offlineReadOnlyBanner(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Stock'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Catálogo'),
                  icon: Icon(Icons.category_outlined),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (Set<int> next) {
                setState(() => _tab = next.first);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              (_tab == 0
                      ? (online
                            ? 'Cantidades oficiales en tienda. '
                                  'Tocá un producto para ver movimientos y ajustar stock.'
                            : 'Mostrando stock en cache (solo lectura). '
                                  'Conectate para ajustar o sincronizar cantidades oficiales.')
                      : (online
                            ? 'Ficha de producto (nombre, SKU, precio, código de barras). '
                                  'Crear/editar requiere conexión.'
                            : 'Catálogo en cache (solo lectura). '
                                  'Crear o editar productos requiere conexión.')) +
                  _countSuffix(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PosSaleUi.textMuted,
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                InventoryStockTab(
                  storeId: widget.storeId,
                  inventoryApi: widget.inventoryApi,
                  productsApi: widget.productsApi,
                  suppliersApi: widget.suppliersApi,
                  storesApi: widget.storesApi,
                  uploadsApi: widget.uploadsApi,
                  localPrefs: widget.localPrefs,
                  catalogInvalidationBus: widget.catalogInvalidationBus,
                  shellOnline: widget.shellOnline,
                  shellInventoryTabActive: widget.shellInventoryTabActive,
                  onLoadedCount: (n) {
                    if (mounted) setState(() => _stockLineCount = n);
                  },
                ),
                ProductCatalogTab(
                  storeId: widget.storeId,
                  productsApi: widget.productsApi,
                  suppliersApi: widget.suppliersApi,
                  storesApi: widget.storesApi,
                  catalogInvalidationBus: widget.catalogInvalidationBus,
                  localPrefs: widget.localPrefs,
                  uploadsApi: widget.uploadsApi,
                  shellOnline: widget.shellOnline,
                  onLoadedCount: (n) {
                    if (mounted) {
                      setState(() => _catalogProductCount = n);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
