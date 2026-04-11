import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/api/exchange_rates_api.dart';
import 'core/api/inventory_api.dart';
import 'core/api/products_api.dart';
import 'core/api/purchases_api.dart';
import 'core/api/sale_returns_api.dart';
import 'core/api/sales_api.dart';
import 'core/api/stores_api.dart';
import 'core/api/suppliers_api.dart';
import 'core/api/sync_api.dart';
import 'core/api/uploads_api.dart';
import 'core/catalog/catalog_invalidation_bus.dart';
import 'core/config/app_config.dart';
import 'core/network/api_connectivity_debug.dart';
import 'core/network/backend_origin_resolver.dart';
import 'core/network/connectivity_util.dart';
import 'core/storage/local_prefs.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/quickmarket_shell_theme.dart';
import 'features/settings/link_store_screen.dart';
import 'features/shell/main_shell.dart';

class QuickPosApp extends StatefulWidget {
  const QuickPosApp({super.key, required this.localPrefs});

  final LocalPrefs localPrefs;

  @override
  State<QuickPosApp> createState() => _QuickPosAppState();
}

class _QuickPosAppState extends State<QuickPosApp> {
  late final ApiClient _apiClient;
  late final StoresApi _storesApi;
  late final ExchangeRatesApi _exchangeRatesApi;
  late final InventoryApi _inventoryApi;
  late final ProductsApi _productsApi;
  late final SalesApi _salesApi;
  late final PurchasesApi _purchasesApi;
  late final SaleReturnsApi _saleReturnsApi;
  late final SuppliersApi _suppliersApi;
  late final SyncApi _syncApi;
  late final UploadsApi _uploadsApi;
  late final CatalogInvalidationBus _catalogInvalidationBus;
  String? _storeId;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _catalogInvalidationBus = CatalogInvalidationBus();
    _apiClient = ApiClient();
    _storesApi = StoresApi(_apiClient);
    _exchangeRatesApi = ExchangeRatesApi(_apiClient);
    _inventoryApi = InventoryApi(_apiClient);
    _productsApi = ProductsApi(_apiClient);
    _salesApi = SalesApi(_apiClient);
    _purchasesApi = PurchasesApi(_apiClient);
    _saleReturnsApi = SaleReturnsApi(_apiClient);
    _suppliersApi = SuppliersApi(_apiClient);
    _syncApi = SyncApi(_apiClient);
    _uploadsApi = UploadsApi(_apiClient);
    _bootstrap();
  }

  Future<void> _tryAutoResolveApiBaseIfNeeded() async {
    final existing = await widget.localPrefs.getApiBaseUrlOverride();
    if (existing != null && existing.isNotEmpty) {
      traceApiConnectivity(
        'Auto-resolve omitido: ya hay API_BASE override → $existing',
      );
      return;
    }

    List<ConnectivityResult> conn;
    try {
      conn = await Connectivity().checkConnectivity();
    } catch (e) {
      traceApiConnectivity(
        'Auto-resolve omitido: checkConnectivity error → $e',
      );
      return;
    }
    if (!connectivityAppearsOnline(conn)) {
      traceApiConnectivity(
        'Auto-resolve omitido: sin conectividad aparente → $conn',
      );
      return;
    }

    final resolver = BackendOriginResolver();
    final vercel = await resolver.fetchFromVercel();
    if (vercel != null) {
      await widget.localPrefs.setPersistedApiOrigin(
        vercel.baseUrl,
        vercel.updatedAt,
      );
    } else {
      traceApiConnectivity(
        'Vercel no devolvió URL (timeout/red/JSON); se usa origen guardado si hay',
      );
    }

    final origin =
        vercel?.baseUrl ?? await widget.localPrefs.getPersistedApiOrigin();
    if (origin == null || origin.isEmpty) {
      traceApiConnectivity('Sin origen (Vercel + prefs vacíos)');
      return;
    }

    final apiV1 = apiV1BaseFromOrigin(origin);
    if (apiV1.isEmpty) return;

    final storeRaw = await widget.localPrefs.getStoreId();
    final storeId = storeRaw?.trim();
    var ok = false;
    if (storeId != null && storeId.isNotEmpty) {
      traceApiConnectivity(
        'Validando API con GET business-settings (storeId presente)…',
      );
      final c = ApiClient(baseUrl: apiV1);
      try {
        await StoresApi(c).getBusinessSettings(storeId);
        ok = true;
        traceApiConnectivity('business-settings OK → se guarda override');
      } catch (e) {
        traceApiConnectivity('business-settings falló: $e');
      }
      c.close();
    } else {
      ok = await probeApiV1Reachable(apiV1);
      if (!ok) {
        traceApiConnectivity(
          'Probe falló (p. ej. ngrok caído); el origen igual quedó en prefs',
        );
      }
    }

    if (ok) {
      await widget.localPrefs.setApiBaseUrlOverride(
        apiV1,
        followCloudResolver: true,
      );
      AppConfig.setRuntimeApiBaseUrlOverride(apiV1);
    }
  }

  Future<void> _bootstrap() async {
    await widget.localPrefs.getOrCreateDeviceId();
    await _tryAutoResolveApiBaseIfNeeded();
    final apiOverride = await widget.localPrefs.getApiBaseUrlOverride();
    if (apiOverride != null && apiOverride.isNotEmpty) {
      AppConfig.setRuntimeApiBaseUrlOverride(apiOverride);
      traceApiConnectivity('Efectiva: override prefs → $apiOverride');
    } else {
      final origin = await widget.localPrefs.getPersistedApiOrigin();
      final derived = (origin != null && origin.isNotEmpty)
          ? apiV1BaseFromOrigin(origin)
          : '';
      if (derived.isNotEmpty) {
        AppConfig.setRuntimeApiBaseUrlOverride(derived);
        traceApiConnectivity(
          'Efectiva: origen nube persistido → $derived '
          '(probe/settings no confirmaron; misma base que Postman/ngrok)',
        );
      } else {
        AppConfig.setRuntimeApiBaseUrlOverride(null);
        traceApiConnectivity(
          'Efectiva: dart-define/default → ${AppConfig.effectiveApiBaseUrl}',
        );
      }
    }
    final id = await widget.localPrefs.getStoreId();
    final trimmed = id?.trim();
    if (!mounted) return;
    setState(() {
      _storeId = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
      _booting = false;
    });
  }

  Future<void> _onLinked(String storeId) async {
    await widget.localPrefs.setStoreId(storeId);
    if (!mounted) return;
    setState(() => _storeId = storeId);
  }

  Future<void> _onChangeStore() async {
    await widget.localPrefs.clearStoreId();
    if (!mounted) return;
    setState(() => _storeId = null);
  }

  @override
  void dispose() {
    _catalogInvalidationBus.dispose();
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quick POS',
      theme: _storeId == null
          ? AppTheme.light()
          : QuickMarketShellTheme.theme(),
      home: _booting
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : _storeId == null
          ? LinkStoreScreen(
              storesApi: _storesApi,
              exchangeRatesApi: _exchangeRatesApi,
              onLinked: _onLinked,
              localPrefs: widget.localPrefs,
            )
          : MainShell(
              storeId: _storeId!,
              storesApi: _storesApi,
              exchangeRatesApi: _exchangeRatesApi,
              inventoryApi: _inventoryApi,
              productsApi: _productsApi,
              salesApi: _salesApi,
              purchasesApi: _purchasesApi,
              saleReturnsApi: _saleReturnsApi,
              suppliersApi: _suppliersApi,
              syncApi: _syncApi,
              uploadsApi: _uploadsApi,
              catalogInvalidationBus: _catalogInvalidationBus,
              onChangeStore: _onChangeStore,
              localPrefs: widget.localPrefs,
            ),
    );
  }
}
