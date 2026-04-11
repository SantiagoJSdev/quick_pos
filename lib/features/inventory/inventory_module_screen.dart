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
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final SuppliersApi suppliersApi;
  final StoresApi storesApi;
  final UploadsApi? uploadsApi;
  final LocalPrefs localPrefs;
  final CatalogInvalidationBus catalogInvalidationBus;

  /// Desde [MainShell]: en offline se usa caché sin esperar timeouts de red.
  final bool shellOnline;

  /// `true` cuando la pestaña principal del shell es Inventario (refresca lista al volver).
  final bool shellInventoryTabActive;

  @override
  State<InventoryModuleScreen> createState() => _InventoryModuleScreenState();
}

class _InventoryModuleScreenState extends State<InventoryModuleScreen> {
  int _tab = 0;
  int? _stockLineCount;
  int? _catalogProductCount;

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

  @override
  Widget build(BuildContext context) {
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
                      ? 'Cantidades en tienda. Tocá un producto para ver movimientos y ajustar stock.'
                      : 'Ficha de producto (nombre, SKU, precio, código de barras). Acá creás y editás productos.') +
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
                    if (mounted) setState(() => _catalogProductCount = n);
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
