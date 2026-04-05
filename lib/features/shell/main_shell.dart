import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/api/exchange_rates_api.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/purchases_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/network/connectivity_util.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/sync_cycle.dart';
import '../inventory/inventory_module_screen.dart';
import '../settings/store_dashboard_screen.dart';
import '../sale/sales_module_screen.dart';
import '../suppliers/suppliers_list_screen.dart';

/// Navegación principal: **Inicio**, **Inventario**, **Venta** (menú → POS / historial / precios), **Proveedores** (C1/C2).
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
    required this.purchasesApi,
    required this.syncApi,
    required this.catalogInvalidationBus,
    required this.onChangeStore,
    required this.localPrefs,
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final SalesApi salesApi;
  final PurchasesApi purchasesApi;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final VoidCallback onChangeStore;
  final LocalPrefs localPrefs;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  static const _syncDebounce = Duration(seconds: 8);
  static const _syncPeriodic = Duration(minutes: 4);

  Timer? _periodicSync;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  List<ConnectivityResult>? _lastConn;
  DateTime? _lastAutoSyncAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runAutoSync(reason: 'startup'));
    });
    unawaited(_initConnectivityHooks());
  }

  Future<void> _initConnectivityHooks() async {
    try {
      _lastConn = await Connectivity().checkConnectivity();
    } catch (_) {}
    _connSub = Connectivity().onConnectivityChanged.listen((next) {
      if (connectivityTransitionedToOnline(_lastConn, next)) {
        unawaited(_runAutoSync(reason: 'connectivity'));
      }
      _lastConn = List<ConnectivityResult>.from(next);
    });
    _periodicSync = Timer.periodic(_syncPeriodic, (_) {
      unawaited(_runAutoSync(reason: 'periodic'));
    });
  }

  /// [startup] sin debounce; el resto evita ráfagas (resume + conectividad + timer).
  Future<void> _runAutoSync({required String reason}) async {
    if (!mounted) return;
    final now = DateTime.now();
    if (reason != 'startup' &&
        _lastAutoSyncAt != null &&
        now.difference(_lastAutoSyncAt!) < _syncDebounce) {
      return;
    }
    if (reason == 'periodic' || reason == 'resumed') {
      try {
        final c = await Connectivity().checkConnectivity();
        if (!connectivityAppearsOnline(c)) return;
      } catch (_) {
        return;
      }
    }
    _lastAutoSyncAt = now;
    final t = await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;
    unawaited(
      runSyncCycle(
        storeId: widget.storeId,
        prefs: widget.localPrefs,
        syncApi: widget.syncApi,
        deviceId: t.deviceId,
        appVersion: t.appVersion,
        catalogInvalidation: widget.catalogInvalidationBus,
        doPull: true,
        doFlush: true,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runAutoSync(reason: 'resumed'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _periodicSync?.cancel();
    _connSub?.cancel();
    super.dispose();
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
            catalogInvalidationBus: widget.catalogInvalidationBus,
          ),
          SalesModuleScreen(
            storeId: widget.storeId,
            productsApi: widget.productsApi,
            storesApi: widget.storesApi,
            exchangeRatesApi: widget.exchangeRatesApi,
            salesApi: widget.salesApi,
            syncApi: widget.syncApi,
            catalogInvalidationBus: widget.catalogInvalidationBus,
            localPrefs: widget.localPrefs,
          ),
          SuppliersListScreen(
            storeId: widget.storeId,
            localPrefs: widget.localPrefs,
            storesApi: widget.storesApi,
            exchangeRatesApi: widget.exchangeRatesApi,
            productsApi: widget.productsApi,
            purchasesApi: widget.purchasesApi,
            syncApi: widget.syncApi,
            catalogInvalidationBus: widget.catalogInvalidationBus,
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
