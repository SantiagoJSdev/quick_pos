import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/exchange_rates_api.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/sync_cycle.dart';
import '../inventory/inventory_module_screen.dart';
import '../settings/store_dashboard_screen.dart';
import '../sale/pos_sale_screen.dart';
import '../suppliers/suppliers_list_screen.dart';

/// Navegación principal: **Inicio**, **Inventario**, **Venta** (POS + cola `sync/push`), **Proveedores** (C1/C2).
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
    required this.salesApi,
    required this.syncApi,
    required this.onChangeStore,
    required this.localPrefs,
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final SalesApi salesApi;
  final SyncApi syncApi;
  final VoidCallback onChangeStore;
  final LocalPrefs localPrefs;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final t = await PosTerminalInfo.load(widget.localPrefs);
      if (!mounted) return;
      unawaited(
        runSyncCycle(
          storeId: widget.storeId,
          prefs: widget.localPrefs,
          syncApi: widget.syncApi,
          deviceId: t.deviceId,
          appVersion: t.appVersion,
          doPull: true,
          doFlush: true,
        ),
      );
    });
  }

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
            localPrefs: widget.localPrefs,
          ),
          PosSaleScreen(
            storeId: widget.storeId,
            productsApi: widget.productsApi,
            storesApi: widget.storesApi,
            exchangeRatesApi: widget.exchangeRatesApi,
            salesApi: widget.salesApi,
            syncApi: widget.syncApi,
            localPrefs: widget.localPrefs,
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
