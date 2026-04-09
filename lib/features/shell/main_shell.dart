import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/api/exchange_rates_api.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/purchases_api.dart';
import '../../core/api/sale_returns_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/api/uploads_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/catalog/catalog_offline_sync.dart';
import '../../core/network/connectivity_util.dart';
import '../../core/photos/product_photo_upload_sync.dart';
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
    required this.saleReturnsApi,
    required this.suppliersApi,
    required this.syncApi,
    required this.uploadsApi,
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
  final SaleReturnsApi saleReturnsApi;
  final SuppliersApi suppliersApi;
  final SyncApi syncApi;
  final UploadsApi uploadsApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final VoidCallback onChangeStore;
  final LocalPrefs localPrefs;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  static const _syncDebounce = Duration(seconds: 8);
  static const _syncPeriodic = Duration(seconds: 90);
  static const _healthProbePeriodic = Duration(seconds: 15);

  Timer? _periodicSync;
  Timer? _healthProbeTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  List<ConnectivityResult>? _lastConn;
  DateTime? _lastAutoSyncAt;
  bool _autoSyncBusy = false;
  bool _isOnline = true;
  bool _backendReachable = true;
  bool _manualForceOffline = false;

  void _recomputeOnlineFlag() {
    final hasNetwork =
        connectivityAppearsOnline(_lastConn ?? const [ConnectivityResult.none]);
    _isOnline = !_manualForceOffline && hasNetwork && _backendReachable;
  }

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
      _recomputeOnlineFlag();
      if (mounted) setState(() {});
    } catch (_) {}
    _connSub = Connectivity().onConnectivityChanged.listen((next) {
      final prev = _lastConn;
      _lastConn = List<ConnectivityResult>.from(next);
      if (mounted) {
        setState(_recomputeOnlineFlag);
      }
      if (connectivityTransitionedToOnline(prev, next)) {
        unawaited(_runAutoSync(reason: 'connectivity'));
      }
    });
    _periodicSync = Timer.periodic(_syncPeriodic, (_) {
      unawaited(_runAutoSync(reason: 'periodic'));
    });
    _healthProbeTimer = Timer.periodic(_healthProbePeriodic, (_) {
      unawaited(_probeBackendHealth());
    });
    unawaited(_probeBackendHealth());
  }

  Future<void> _probeBackendHealth() async {
    if (!mounted || _manualForceOffline) return;
    final hasNetwork =
        connectivityAppearsOnline(_lastConn ?? const [ConnectivityResult.none]);
    if (!hasNetwork) {
      if (_backendReachable) {
        _backendReachable = false;
        if (mounted) setState(_recomputeOnlineFlag);
      }
      return;
    }
    final wasReachable = _backendReachable;
    try {
      await widget.storesApi.getBusinessSettings(widget.storeId);
      if (!_backendReachable) {
        _backendReachable = true;
        if (mounted) setState(_recomputeOnlineFlag);
      }
      if (!wasReachable &&
          _backendReachable &&
          !_manualForceOffline &&
          mounted) {
        unawaited(_runAutoSync(reason: 'backend-recovered'));
      }
    } catch (_) {
      if (_backendReachable) {
        _backendReachable = false;
        if (mounted) setState(_recomputeOnlineFlag);
      }
    }
  }

  /// [startup] y [backend-recovered] sin debounce; el resto evita ráfagas.
  Future<void> _runAutoSync({required String reason}) async {
    if (!mounted) return;
    if (_manualForceOffline) return;
    if (_autoSyncBusy) return;
    final now = DateTime.now();
    if (reason != 'startup' &&
        reason != 'backend-recovered' &&
        _lastAutoSyncAt != null &&
        now.difference(_lastAutoSyncAt!) < _syncDebounce) {
      return;
    }
    if (reason == 'periodic' ||
        reason == 'resumed' ||
        reason == 'backend-recovered') {
      try {
        final c = await Connectivity().checkConnectivity();
        if (!connectivityAppearsOnline(c)) return;
      } catch (_) {
        return;
      }
    }
    _autoSyncBusy = true;
    _lastAutoSyncAt = now;
    try {
      final t = await PosTerminalInfo.load(widget.localPrefs);
      if (!mounted) return;
      final cycle = await runSyncCycle(
        storeId: widget.storeId,
        prefs: widget.localPrefs,
        syncApi: widget.syncApi,
        deviceId: t.deviceId,
        appVersion: t.appVersion,
        catalogInvalidation: widget.catalogInvalidationBus,
        doPull: true,
        doFlush: true,
      );
      _backendReachable = cycle.pullError == null &&
          !cycle.flush.hadTransportFailure &&
          !cycle.flush.hadRetryableFailure;
      if (mounted) {
        setState(_recomputeOnlineFlag);
      }
      await flushPendingCatalogMutations(
        storeId: widget.storeId,
        prefs: widget.localPrefs,
        productsApi: widget.productsApi,
        catalogInvalidation: widget.catalogInvalidationBus,
      );
      await flushPendingProductPhotoUploads(
        storeId: widget.storeId,
        prefs: widget.localPrefs,
        uploader: (entry) async {
          final upload = await widget.uploadsApi.uploadProductImage(
            widget.storeId,
            filePath: entry.localFilePath,
          );
          final updated = await widget.productsApi.associateProductImage(
            widget.storeId,
            entry.productId,
            imageUrl: upload.url,
          );
          final cache = await widget.localPrefs.loadCatalogProductsCache();
          final i = cache.indexWhere((p) => p.id == updated.id);
          if (i >= 0) {
            cache[i] = updated;
          } else {
            cache.add(updated);
          }
          await widget.localPrefs.saveCatalogProductsCache(cache);
          widget.catalogInvalidationBus
              .invalidateFromLocalMutation(productIds: {updated.id});
        },
      );
      if (mounted) setState(_recomputeOnlineFlag);
    } catch (_) {
      _backendReachable = false;
      if (mounted) {
        setState(_recomputeOnlineFlag);
      }
    } finally {
      _autoSyncBusy = false;
    }
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
    _healthProbeTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
              KeyedSubtree(
                key: const ValueKey<String>('shell_tab_inicio'),
                child: StoreDashboardScreen(
                  storeId: widget.storeId,
                  storesApi: widget.storesApi,
                  exchangeRatesApi: widget.exchangeRatesApi,
                  onChangeStore: widget.onChangeStore,
                  localPrefs: widget.localPrefs,
                  forcedOffline: _manualForceOffline,
                  onlineStatus: _isOnline,
                  onToggleConnectivityMode: () {
                    setState(() {
                      _manualForceOffline = !_manualForceOffline;
                      if (!_manualForceOffline) {
                        _backendReachable = true;
                      }
                      _recomputeOnlineFlag();
                    });
                    if (!_manualForceOffline) {
                      unawaited(_runAutoSync(reason: 'manual-online'));
                      unawaited(_probeBackendHealth());
                    }
                  },
                ),
              ),
              KeyedSubtree(
                key: const ValueKey<String>('shell_tab_inventario'),
                child: InventoryModuleScreen(
                  storeId: widget.storeId,
                  inventoryApi: widget.inventoryApi,
                  productsApi: widget.productsApi,
                  suppliersApi: widget.suppliersApi,
                  storesApi: widget.storesApi,
                  uploadsApi: widget.uploadsApi,
                  localPrefs: widget.localPrefs,
                  catalogInvalidationBus: widget.catalogInvalidationBus,
                ),
              ),
              KeyedSubtree(
                key: const ValueKey<String>('shell_tab_venta'),
                child: SalesModuleScreen(
                  storeId: widget.storeId,
                  productsApi: widget.productsApi,
                  storesApi: widget.storesApi,
                  exchangeRatesApi: widget.exchangeRatesApi,
                  salesApi: widget.salesApi,
                  saleReturnsApi: widget.saleReturnsApi,
                  syncApi: widget.syncApi,
                  catalogInvalidationBus: widget.catalogInvalidationBus,
                  localPrefs: widget.localPrefs,
                ),
              ),
              KeyedSubtree(
                key: const ValueKey<String>('shell_tab_proveedores'),
                child: SuppliersListScreen(
                  storeId: widget.storeId,
                  localPrefs: widget.localPrefs,
                  storesApi: widget.storesApi,
                  exchangeRatesApi: widget.exchangeRatesApi,
                  productsApi: widget.productsApi,
                  purchasesApi: widget.purchasesApi,
                  suppliersApi: widget.suppliersApi,
                  syncApi: widget.syncApi,
                  catalogInvalidationBus: widget.catalogInvalidationBus,
                ),
              ),
            ],
          ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _isOnline ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isOnline ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
          NavigationBar(
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
        ],
      ),
    );
  }
}
