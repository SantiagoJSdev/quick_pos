import 'package:flutter/material.dart';

import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import 'inventory_stock_tab.dart';
import 'product_catalog_tab.dart';

/// Pestaña **Inventario**: **Stock** (B1) y **Catálogo** (B4–B6) con [SegmentedButton].
class InventoryModuleScreen extends StatefulWidget {
  const InventoryModuleScreen({
    super.key,
    required this.storeId,
    required this.inventoryApi,
    required this.productsApi,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;

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
      appBar: AppBar(title: const Text('Inventario')),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  onLoadedCount: (n) {
                    if (mounted) setState(() => _stockLineCount = n);
                  },
                ),
                ProductCatalogTab(
                  storeId: widget.storeId,
                  productsApi: widget.productsApi,
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
