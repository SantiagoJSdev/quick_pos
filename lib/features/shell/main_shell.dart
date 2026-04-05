import 'package:flutter/material.dart';

import '../../core/api/exchange_rates_api.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/storage/local_prefs.dart';
import '../inventory/inventory_module_screen.dart';
import '../settings/store_dashboard_screen.dart';
import '../sale/pos_sale_screen.dart';
import '../suppliers/suppliers_list_screen.dart';

/// Navegación principal: **Inicio**, **Inventario**, **Venta** (P1 catálogo + escáner + ticket mínimo), **Proveedores** (C1/C2).
///
/// Usa [IndexedStack] para conservar el estado de cada pestaña al cambiar.
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.storeId,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.inventoryApi,
    required this.productsApi,
    required this.onChangeStore,
    required this.localPrefs,
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final VoidCallback onChangeStore;
  final LocalPrefs localPrefs;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          StoreDashboardScreen(
            storeId: widget.storeId,
            storesApi: widget.storesApi,
            exchangeRatesApi: widget.exchangeRatesApi,
            onChangeStore: widget.onChangeStore,
          ),
          InventoryModuleScreen(
            storeId: widget.storeId,
            inventoryApi: widget.inventoryApi,
            productsApi: widget.productsApi,
          ),
          PosSaleScreen(
            storeId: widget.storeId,
            productsApi: widget.productsApi,
          ),
          SuppliersListScreen(localPrefs: widget.localPrefs),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventario',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Venta',
          ),
          NavigationDestination(
            icon: Icon(Icons.local_shipping_outlined),
            selectedIcon: Icon(Icons.local_shipping),
            label: 'Proveedores',
          ),
        ],
      ),
    );
  }
}
