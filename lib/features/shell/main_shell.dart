import 'package:flutter/material.dart';

import '../../core/api/exchange_rates_api.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/stores_api.dart';
import '../inventory/inventory_module_screen.dart';
import '../settings/store_dashboard_screen.dart';
import 'placeholder_module_screen.dart';

/// Navegación principal: **Inicio**, **Inventario** (Stock B1 + Catálogo B4–B6), placeholders POS / proveedores.
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
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final VoidCallback onChangeStore;

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
          const PlaceholderModuleScreen(
            title: 'Punto de venta',
            message:
                'Carrito, búsqueda y escaneo de código de barras con la cámara (Sprint 2).',
            icon: Icons.point_of_sale_outlined,
          ),
          const PlaceholderModuleScreen(
            title: 'Proveedores',
            message:
                'Lista local de proveedores (nombre + UUID) hasta que exista API.',
            icon: Icons.local_shipping_outlined,
          ),
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
