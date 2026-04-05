import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/api/exchange_rates_api.dart';
import 'core/api/inventory_api.dart';
import 'core/api/products_api.dart';
import 'core/api/stores_api.dart';
import 'core/storage/local_prefs.dart';
import 'core/theme/app_theme.dart';
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
  String? _storeId;
  bool _booting = true;

  @override
  void initState() {
    super.initState();
    _apiClient = ApiClient();
    _storesApi = StoresApi(_apiClient);
    _exchangeRatesApi = ExchangeRatesApi(_apiClient);
    _inventoryApi = InventoryApi(_apiClient);
    _productsApi = ProductsApi(_apiClient);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await widget.localPrefs.getOrCreateDeviceId();
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
    _apiClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Quick POS',
      theme: AppTheme.light(),
      home: _booting
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _storeId == null
              ? LinkStoreScreen(
                  storesApi: _storesApi,
                  exchangeRatesApi: _exchangeRatesApi,
                  onLinked: _onLinked,
                )
              : MainShell(
                  storeId: _storeId!,
                  storesApi: _storesApi,
                  exchangeRatesApi: _exchangeRatesApi,
                  inventoryApi: _inventoryApi,
                  productsApi: _productsApi,
                  onChangeStore: _onChangeStore,
                ),
    );
  }
}
