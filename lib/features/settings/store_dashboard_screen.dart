import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/models/business_settings.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/widgets/quickmarket_branding.dart';
import '../sale/pos_sale_ui_tokens.dart';
import 'exchange_rate_today_screen.dart';
import 'register_exchange_rate_screen.dart';
import 'store_advanced_config_screen.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({
    super.key,
    required this.storeId,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.onChangeStore,
    required this.localPrefs,
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final VoidCallback onChangeStore;
  final LocalPrefs localPrefs;

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  late Future<BusinessSettings> _future;
  bool _settingsFromCache = false;
  bool _terminalLoading = true;
  String? _deviceId;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    _future = _loadSettingsWithCache();
    unawaited(_loadTerminal());
  }

  Future<BusinessSettings> _loadSettingsWithCache() async {
    try {
      final s = await widget.storesApi.getBusinessSettings(widget.storeId);
      await widget.localPrefs.saveBusinessSettingsCache(
        widget.storeId,
        {
          'id': s.id,
          'storeId': s.storeId,
          'defaultMarginPercent': s.defaultMarginPercent,
          'functionalCurrency': {
            'code': s.functionalCurrency.code,
            'name': s.functionalCurrency.name,
          },
          'defaultSaleDocCurrency': s.defaultSaleDocCurrency == null
              ? null
              : {
                  'code': s.defaultSaleDocCurrency!.code,
                  'name': s.defaultSaleDocCurrency!.name,
                },
          'store': {
            'name': s.storeName,
            'type': s.storeType,
          },
        },
      );
      _settingsFromCache = false;
      return s;
    } catch (_) {
      final cached = await widget.localPrefs.loadBusinessSettingsCache(widget.storeId);
      if (cached != null) {
        _settingsFromCache = true;
        return cached;
      }
      rethrow;
    }
  }

  Future<void> _loadTerminal() async {
    final t = await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;
    setState(() {
      _deviceId = t.deviceId;
      _appVersion = t.appVersion;
      _terminalLoading = false;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadSettingsWithCache();
    });
    await _future;
  }

  Future<void> _openPinProtectedConfig() async {
    final ok = await showStoreConfigPinDialog(context);
    if (!mounted || ok != true) return;
    // Evita apilar la ruta mientras el overlay del diálogo aún se retira (GlobalKey duplicado).
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) => StoreAdvancedConfigScreen(
          storeId: widget.storeId,
          storesApi: widget.storesApi,
          localPrefs: widget.localPrefs,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  Future<void> _confirmDesvincular() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular tienda'),
        content: const Text(
          'Se borrará la tienda guardada en este dispositivo. '
          'Podrás enlazar o crear otra cuando quieras. '
          'Los datos del servidor no se eliminan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      widget.onChangeStore();
    }
  }

  void _closeApp() {
    SystemNavigator.pop();
  }

  Widget _functionalCurrencyCard(
    BuildContext context,
    BusinessSettings s,
  ) {
    final code = s.functionalCurrency.code;
    final name = s.functionalCurrency.name;
    final value = code.isEmpty
        ? '—'
        : ((name != null && name.isNotEmpty) ? '$code — $name' : code);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Moneda funcional',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: PosSaleUi.text,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: PosSaleUi.text,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Moneda de referencia para inventario y costos (p. ej. USD). '
              'La moneda del ticket en caja la define el servidor al facturar.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PosSaleUi.textMuted,
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _terminalInfoCard(BuildContext context) {
    if (_terminalLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 16),
        child: LinearProgressIndicator(),
      );
    }
    final id = _deviceId;
    final ver = _appVersion ?? '—';
    if (id == null) return const SizedBox.shrink();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Este terminal',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: PosSaleUi.text,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'App $ver',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: PosSaleUi.textMuted,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    id,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: PosSaleUi.text,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar ID',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('deviceId copiado')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Varios equipos pueden usar la misma tienda (mismo enlace). Cada '
              'instalación tiene su propio deviceId para ventas, historial y sync.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PosSaleUi.textMuted,
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const QuickMarketWordmark(logoSize: 32, fontSize: 17, gap: 10),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _refresh(),
            tooltip: 'Actualizar',
          ),
          TextButton(
            onPressed: _confirmDesvincular,
            child: const Text('Desvincular'),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: _closeApp,
            tooltip: 'Cerrar aplicación',
          ),
        ],
      ),
      body: FutureBuilder<BusinessSettings>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final err = snapshot.error;
            String msg = err.toString();
            if (err is ApiError) {
              msg = err.userMessageForSupport;
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      msg,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: PosSaleUi.textMuted),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _refresh,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            );
          }
          final s = snapshot.data!;
          final doc = s.defaultSaleDocCurrency;
          return RefreshIndicator(
            onRefresh: _refresh,
            color: PosSaleUi.primary,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  s.storeName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: PosSaleUi.text,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (s.storeType != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.storeType!,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: PosSaleUi.textMuted,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                _terminalInfoCard(context),
                const SizedBox(height: 16),
                if (_settingsFromCache) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.orange.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'Mostrando configuración cacheada (modo offline).',
                      style: TextStyle(fontSize: 12, color: Colors.orange),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _functionalCurrencyCard(context, s),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: _openPinProtectedConfig,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: const Text('Configuración (clave)'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Margen por defecto de la tienda e ID de tienda (copiar). '
                  'Solo personal autorizado.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PosSaleUi.textMuted,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => ExchangeRateTodayScreen(
                          storeId: widget.storeId,
                          exchangeRatesApi: widget.exchangeRatesApi,
                          localPrefs: widget.localPrefs,
                          initialBase: s.functionalCurrency.code,
                          initialQuote: doc?.code,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.currency_exchange),
                  label: const Text('Tasa del día'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: PosSaleUi.surface3,
                    foregroundColor: PosSaleUi.text,
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => RegisterExchangeRateScreen(
                          storeId: widget.storeId,
                          exchangeRatesApi: widget.exchangeRatesApi,
                          initialBase: s.functionalCurrency.code,
                          initialQuote: doc?.code,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_chart_outlined),
                  label: const Text('Registrar nueva tasa'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _confirmDesvincular,
                  icon: const Icon(Icons.link_off_outlined),
                  label: const Text('Desvincular tienda'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: _closeApp,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Cerrar aplicación'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: PosSaleUi.textMuted,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
