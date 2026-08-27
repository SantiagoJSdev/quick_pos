import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../../core/api/cash_sessions_api.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/payment_methods_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/purchases_api.dart';
import '../../core/api/sale_returns_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/api/uploads_api.dart';
import '../../features/dashboard/data/dashboard_repository.dart';
import '../../core/cash/cash_session_service.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/network/api_connectivity_debug.dart';
import '../../core/network/connectivity_util.dart';
import '../../core/photos/pending_product_photo_upload_entry.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/device_hydrate_sync.dart';
import '../inventory/inventory_module_screen.dart';
import '../settings/module_not_enabled_screen.dart';
import '../settings/store_dashboard_screen.dart';
import '../sale/sales_module_screen.dart';
import 'shell_online_scope.dart';
import '../suppliers/suppliers_module_screen.dart';

/// Navegación principal: **Inicio**, **Inventario**, **Venta** (menú → POS / historial / precios), **Proveedores** (C1/C2).
///
/// Usa [IndexedStack] para conservar el estado de cada pestaña al cambiar.
///
/// **Sin sync en segundo plano:** no hay timer, ni hydrate al resume/arranque/
/// reconectar. El backend solo se toca con Sincronizar, cierre/apertura de caja,
/// Inventario, Proveedores, o un gesto explícito (Poner Online / reintentar).
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.storeId,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.inventoryApi,
    required this.productsApi,
    required this.salesApi,
    required this.cashSessionsApi,
    required this.paymentMethodsApi,
    required this.purchasesApi,
    required this.saleReturnsApi,
    required this.suppliersApi,
    required this.syncApi,
    required this.uploadsApi,
    required this.catalogInvalidationBus,
    required this.dashboardRepository,
    required this.onChangeStore,
    required this.localPrefs,
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final SalesApi salesApi;
  final CashSessionsApi cashSessionsApi;
  final PaymentMethodsApi paymentMethodsApi;
  final PurchasesApi purchasesApi;
  final SaleReturnsApi saleReturnsApi;
  final SuppliersApi suppliersApi;
  final SyncApi syncApi;
  final UploadsApi uploadsApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final DashboardRepository dashboardRepository;
  final Future<void> Function() onChangeStore;
  final LocalPrefs localPrefs;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _probeFailsToGoOffline = 2;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  List<ConnectivityResult>? _lastConn;
  bool _hydrateBusy = false;
  bool _manualHomeSyncBusy = false;
  String? _hydrateStep;
  bool _isOnline = true;
  bool _backendReachable = true;
  bool _manualForceOffline = false;
  int _consecutiveProbeFailures = 0;
  bool _inventoryModuleEnabled = false;
  bool _suppliersModuleEnabled = false;

  void _recomputeOnlineFlag() {
    final hasNetwork = connectivityAppearsOnline(
      _lastConn ?? const [ConnectivityResult.none],
    );
    _isOnline = !_manualForceOffline && hasNetwork && _backendReachable;
  }

  void _onBackendOk() {
    _consecutiveProbeFailures = 0;
    if (!_backendReachable) {
      _backendReachable = true;
      if (mounted) setState(_recomputeOnlineFlag);
    }
  }

  void _onProbeFailure() {
    _consecutiveProbeFailures++;
    if (_consecutiveProbeFailures >= _probeFailsToGoOffline &&
        _backendReachable) {
      _backendReachable = false;
      if (mounted) setState(_recomputeOnlineFlag);
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restoreManualOfflineThenStart());
    unawaited(_loadDeviceModules());
  }

  Future<void> _loadDeviceModules() async {
    final deviceId = await widget.localPrefs.getOrCreateDeviceId();
    final inventory = await widget.localPrefs.isInventoryModuleEnabled(
      storeId: widget.storeId,
      deviceId: deviceId,
    );
    final suppliers = await widget.localPrefs.isSuppliersModuleEnabled(
      storeId: widget.storeId,
      deviceId: deviceId,
    );
    if (!mounted) return;
    setState(() {
      _inventoryModuleEnabled = inventory;
      _suppliersModuleEnabled = suppliers;
    });
  }

  Future<void> _restoreManualOfflineThenStart() async {
    final forced = await widget.localPrefs.getManualForceOffline();
    if (!mounted) return;
    setState(() {
      _manualForceOffline = forced;
      _recomputeOnlineFlag();
    });
    await _initConnectivityHooks();
  }

  Future<void> _initConnectivityHooks() async {
    try {
      _lastConn = await Connectivity().checkConnectivity();
      final hasNetwork = connectivityAppearsOnline(_lastConn!);
      // Optimista: con red asumimos backend OK hasta un fallo explícito.
      _backendReachable = hasNetwork;
      _recomputeOnlineFlag();
      if (mounted) setState(() {});
    } catch (_) {}
    _connSub = Connectivity().onConnectivityChanged.listen((next) {
      final prev = _lastConn;
      _lastConn = List<ConnectivityResult>.from(next);
      final nowOnline = connectivityAppearsOnline(next);
      if (!nowOnline) {
        _backendReachable = false;
      } else if (connectivityTransitionedToOnline(prev, next)) {
        // Solo bandera local: no hydrate ni probe al reconectar.
        _backendReachable = true;
        _consecutiveProbeFailures = 0;
      }
      if (mounted) {
        setState(_recomputeOnlineFlag);
      }
    });
  }

  /// Un solo GET settings (gesto explícito: Poner Online / reintentar Inventario).
  /// No hidrata ni envía cola.
  Future<void> _requestReconnect({String reason = 'manual-retry'}) async {
    if (!mounted) return;
    if (_manualForceOffline) {
      setState(() {
        _manualForceOffline = false;
        _recomputeOnlineFlag();
      });
      unawaited(widget.localPrefs.setManualForceOffline(false));
    }
    try {
      final c = await Connectivity().checkConnectivity();
      _lastConn = List<ConnectivityResult>.from(c);
      if (!connectivityAppearsOnline(c)) {
        _backendReachable = false;
        if (mounted) setState(_recomputeOnlineFlag);
        return;
      }
    } catch (_) {}
    try {
      await widget.storesApi.getBusinessSettings(widget.storeId);
      _onBackendOk();
      if (mounted) setState(_recomputeOnlineFlag);
      traceApiConnectivity('Reconnect OK ($reason)');
    } catch (e) {
      traceApiConnectivity('Reconnect probe falló ($reason): $e');
      _onProbeFailure();
      if (mounted) setState(_recomputeOnlineFlag);
    }
  }

  Future<void> _uploadPendingProductPhoto(
    PendingProductPhotoUploadEntry entry,
  ) async {
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
    widget.catalogInvalidationBus.invalidateFromLocalMutation(
      productIds: {updated.id},
    );
  }

  Future<DeviceHydrateResult> _hydrateDevice({
    void Function(String step)? onProgress,
    bool requireEmptyQueue = false,
  }) async {
    final t = await PosTerminalInfo.load(widget.localPrefs);
    return hydrateDeviceFromServer(
      storeId: widget.storeId,
      prefs: widget.localPrefs,
      syncApi: widget.syncApi,
      productsApi: widget.productsApi,
      inventoryApi: widget.inventoryApi,
      storesApi: widget.storesApi,
      exchangeRatesApi: widget.exchangeRatesApi,
      deviceId: t.deviceId,
      appVersion: t.appVersion,
      catalogInvalidation: widget.catalogInvalidationBus,
      cashSessions: CashSessionService(
        prefs: widget.localPrefs,
        api: widget.cashSessionsApi,
      ),
      photoUploader: _uploadPendingProductPhoto,
      onProgress: onProgress,
      requireEmptyQueue: requireEmptyQueue,
    );
  }

  /// Sync manual desde Inicio: **solo online**. Loading hasta terminar.
  Future<void> _runManualSyncFromHome() async {
    if (!mounted || _manualHomeSyncBusy) return;
    final messenger = ScaffoldMessenger.maybeOf(context);

    if (_manualForceOffline) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Estás en modo Offline. Tocá «Poner Online» y esperá '
            'conexión antes de sincronizar.',
          ),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _manualHomeSyncBusy = true;
      _hydrateStep = 'Comprobando servidor…';
    });
    try {
      try {
        final c = await Connectivity().checkConnectivity();
        if (!connectivityAppearsOnline(c)) {
          if (mounted) {
            setState(() {
              _backendReachable = false;
              _recomputeOnlineFlag();
            });
          }
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(
                'Sin red. Conectate a internet para sincronizar.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
      } catch (_) {}

      try {
        await widget.storesApi.getBusinessSettings(widget.storeId);
        if (mounted) {
          setState(() {
            _backendReachable = true;
            _consecutiveProbeFailures = 0;
            _recomputeOnlineFlag();
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _backendReachable = false;
            _recomputeOnlineFlag();
          });
        }
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Servidor no alcanzable. No se sincronizó.\n$e',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }

      if (!_isOnline) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión online. El botón Sincronizar solo funciona online.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      while (_hydrateBusy) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (!mounted) return;
      }
      _hydrateBusy = true;

      final result = await _hydrateDevice(
        onProgress: (s) {
          if (mounted) setState(() => _hydrateStep = s);
        },
      );
      if (!mounted) return;
      if (result.downloadedOk || result.ok) {
        _onBackendOk();
      }
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(result.userMessage),
          duration: Duration(seconds: result.ok ? 5 : 7),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger?.hideCurrentSnackBar();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'Sincronización incompleta. Revisá red/servidor y reintentá.\n$e',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      _hydrateBusy = false;
      if (mounted) {
        setState(() {
          _manualHomeSyncBusy = false;
          _hydrateStep = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellOnlineScope(
      isOnline: _isOnline,
      manualForceOffline: _manualForceOffline,
      backendReachable: _backendReachable,
      child: Stack(
        children: [
          Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            KeyedSubtree(
              key: const ValueKey<String>('shell_tab_inicio'),
              child: StoreDashboardScreen(
                storeId: widget.storeId,
                storesApi: widget.storesApi,
                exchangeRatesApi: widget.exchangeRatesApi,
                dashboardRepository: widget.dashboardRepository,
                onChangeStore: widget.onChangeStore,
                localPrefs: widget.localPrefs,
                forcedOffline: _manualForceOffline,
                onlineStatus: _isOnline,
                syncBusy: _manualHomeSyncBusy,
                onRequestSync: _runManualSyncFromHome,
                onHydrateDevice: _hydrateDevice,
                cashSessionsApi: widget.cashSessionsApi,
                syncApi: widget.syncApi,
                catalogInvalidationBus: widget.catalogInvalidationBus,
                onDeviceModulesChanged: () {
                  unawaited(_loadDeviceModules());
                },
                onBackendTransportFailure: () {
                  if (!mounted) return;
                  _onProbeFailure();
                  if (mounted) setState(_recomputeOnlineFlag);
                },
                onConnectivityModeButtonPressed: () {
                  traceApiConnectivity(
                    'Botón conectividad: online=$_isOnline '
                    'forzadoOffline=$_manualForceOffline '
                    'backendAlcanzable=$_backendReachable',
                  );
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  if (_isOnline) {
                    setState(() {
                      _manualForceOffline = true;
                      _recomputeOnlineFlag();
                    });
                    unawaited(widget.localPrefs.setManualForceOffline(true));
                    messenger?.showSnackBar(
                      const SnackBar(
                        content: Text('Modo offline forzado.'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    traceApiConnectivity(
                      'Tras forzar offline: online=$_isOnline',
                    );
                    return;
                  }
                  if (_manualForceOffline) {
                    setState(() {
                      _manualForceOffline = false;
                      _recomputeOnlineFlag();
                    });
                    unawaited(widget.localPrefs.setManualForceOffline(false));
                  }
                  messenger?.showSnackBar(
                    const SnackBar(
                      content: Text('Reconectando con el servidor…'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  unawaited(_requestReconnect(reason: 'manual-online'));
                },
              ),
            ),
            KeyedSubtree(
              key: const ValueKey<String>('shell_tab_inventario'),
              child: _inventoryModuleEnabled
                  ? InventoryModuleScreen(
                      storeId: widget.storeId,
                      inventoryApi: widget.inventoryApi,
                      productsApi: widget.productsApi,
                      suppliersApi: widget.suppliersApi,
                      storesApi: widget.storesApi,
                      uploadsApi: widget.uploadsApi,
                      localPrefs: widget.localPrefs,
                      catalogInvalidationBus: widget.catalogInvalidationBus,
                      shellOnline: _isOnline,
                      shellInventoryTabActive: _index == 1,
                      onRetryOnline: () =>
                          _requestReconnect(reason: 'inventory-retry'),
                    )
                  : ModuleNotEnabledScreen(
                      moduleTitle: 'Inventario',
                      onGoHome: () => setState(() => _index = 0),
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
                cashSessionsApi: widget.cashSessionsApi,
                paymentMethodsApi: widget.paymentMethodsApi,
                saleReturnsApi: widget.saleReturnsApi,
                syncApi: widget.syncApi,
                uploadsApi: widget.uploadsApi,
                catalogInvalidationBus: widget.catalogInvalidationBus,
                localPrefs: widget.localPrefs,
                shellOnline: _isOnline,
                onHydrateDevice: _hydrateDevice,
              ),
            ),
            KeyedSubtree(
              key: const ValueKey<String>('shell_tab_proveedores'),
              child: _suppliersModuleEnabled
                  ? SuppliersModuleScreen(
                      storeId: widget.storeId,
                      localPrefs: widget.localPrefs,
                      storesApi: widget.storesApi,
                      exchangeRatesApi: widget.exchangeRatesApi,
                      productsApi: widget.productsApi,
                      purchasesApi: widget.purchasesApi,
                      suppliersApi: widget.suppliersApi,
                      syncApi: widget.syncApi,
                      catalogInvalidationBus: widget.catalogInvalidationBus,
                      shellOnline: _isOnline,
                    )
                  : ModuleNotEnabledScreen(
                      moduleTitle: 'Proveedores',
                      onGoHome: () => setState(() => _index = 0),
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
              onDestinationSelected: (i) {
                if (_manualHomeSyncBusy) return;
                setState(() => _index = i);
              },
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
          ),
          if (_manualHomeSyncBusy) ...[
            const ModalBarrier(dismissible: false, color: Color(0x99000000)),
            Center(
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(
                        _hydrateStep ?? 'Sincronizando…',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'No se puede vender ni cambiar de pantalla hasta terminar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
