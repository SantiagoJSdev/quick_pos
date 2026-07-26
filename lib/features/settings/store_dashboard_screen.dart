import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/cash_sessions_api.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/models/business_settings.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/widgets/quickmarket_branding.dart';
import '../dashboard/domain/device_dashboard_config.dart';
import '../dashboard/presentation/screens/dashboard_home_screen.dart';
import '../dashboard/data/dashboard_repository.dart';
import '../sale/cash_close_screen.dart';
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
    required this.dashboardRepository,
    required this.onChangeStore,
    required this.localPrefs,
    required this.forcedOffline,
    required this.onlineStatus,
    required this.onConnectivityModeButtonPressed,
    required this.onBackendTransportFailure,
    this.syncBusy = false,
    this.onRequestSync,
    this.cashSessionsApi,
    this.syncApi,
    this.catalogInvalidationBus,
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final DashboardRepository dashboardRepository;
  final Future<void> Function() onChangeStore;
  final LocalPrefs localPrefs;
  final bool forcedOffline;
  final bool onlineStatus;
  final VoidCallback onConnectivityModeButtonPressed;

  /// Timeout / sin red al cargar settings: el shell marca backend inalcanzable para pasar a offline efectivo.
  final VoidCallback onBackendTransportFailure;

  /// Sync manual (cola + catálogo/precios + tasa). Lo provee [MainShell].
  final bool syncBusy;
  final Future<void> Function()? onRequestSync;

  final CashSessionsApi? cashSessionsApi;
  final SyncApi? syncApi;
  final CatalogInvalidationBus? catalogInvalidationBus;

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  late Future<BusinessSettings> _future;
  bool _settingsFromCache = false;
  bool _terminalLoading = true;
  bool _deviceAccessLoading = true;
  bool _operationalDashboardVisible = false;
  String? _deviceId;
  String? _appVersion;
  DeviceDashboardConfig? _deviceDashboardConfig;

  @override
  void initState() {
    super.initState();
    _future = _loadSettingsWithCache();
    unawaited(_loadTerminal());
    unawaited(_loadDeviceDashboardAccess());
  }

  @override
  void didUpdateWidget(covariant StoreDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.onlineStatus != widget.onlineStatus ||
        oldWidget.forcedOffline != widget.forcedOffline) {
      setState(() {
        _future = _loadSettingsWithCache();
      });
      unawaited(_loadDeviceDashboardAccess());
    }
  }

  Future<void> _loadDeviceDashboardAccess() async {
    final deviceId = _deviceId ?? await widget.localPrefs.getOrCreateDeviceId();
    if (!mounted) return;
    setState(() => _deviceAccessLoading = true);
    final visible = await widget.dashboardRepository
        .operationalDashboardVisibleCached(
          widget.storeId,
          deviceId,
          online: widget.onlineStatus && !widget.forcedOffline,
        );
    if (!mounted) return;
    DeviceDashboardConfig? config;
    if (widget.onlineStatus && !widget.forcedOffline) {
      try {
        config = await widget.dashboardRepository.fetchDeviceConfig(
          widget.storeId,
          deviceId,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _operationalDashboardVisible = visible;
      _deviceDashboardConfig = config;
      _deviceAccessLoading = false;
    });
  }

  Future<BusinessSettings> _loadSettingsWithCache() async {
    if (!widget.onlineStatus || widget.forcedOffline) {
      final cached = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      if (cached != null) {
        _settingsFromCache = true;
        return cached;
      }
      throw StateError(
        'Sin configuración en caché. Conectate o esperá a recuperar red.',
      );
    }
    try {
      final s = await widget.storesApi.getBusinessSettings(widget.storeId);
      await widget.localPrefs.saveBusinessSettingsCache(widget.storeId, {
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
        'store': {'name': s.storeName, 'type': s.storeType},
      });
      _settingsFromCache = false;
      return s;
    } catch (e) {
      if (_isLikelyTransportFailure(e)) {
        widget.onBackendTransportFailure();
      }
      final cached = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      if (cached != null) {
        _settingsFromCache = true;
        return cached;
      }
      rethrow;
    }
  }

  static bool _isLikelyTransportFailure(Object e) {
    if (e is ApiError) return e.isLikelyTransportFailure;
    final blob = e.toString().toLowerCase();
    return blob.contains('socket') ||
        blob.contains('connection') ||
        blob.contains('failed host') ||
        blob.contains('network') ||
        blob.contains('timeout') ||
        blob.contains('tiempo') ||
        blob.contains('clientexception');
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
    await Future.wait([_future, _loadDeviceDashboardAccess()]);
  }

  Future<void> _toggleOperationalDashboard({required bool enable}) async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('deviceId no disponible.')),
      );
      return;
    }
    final pin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DashboardAdminPinDialog(
        title: enable ? 'Habilitar dashboard' : 'Deshabilitar dashboard',
        message: enable
            ? 'Ingresá el PIN del servidor (DASHBOARD_ADMIN_PIN). '
              'La app envía el PATCH con el storeId y deviceId de este equipo.'
            : 'Este equipo dejará de mostrar el dashboard.',
      ),
    );
    if (pin == null || pin.isEmpty || !mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    try {
      if (enable) {
        await widget.dashboardRepository.enableOperationalDashboard(
          storeId: widget.storeId,
          deviceId: deviceId,
          adminPin: pin,
        );
      } else {
        await widget.dashboardRepository.disableOperationalDashboard(
          storeId: widget.storeId,
          deviceId: deviceId,
          adminPin: pin,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enable
                ? 'Dashboard habilitado en el servidor. Token guardado en este dispositivo.'
                : 'Dashboard deshabilitado en este dispositivo.',
          ),
        ),
      );
      await _loadDeviceDashboardAccess();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_dashboardPatchErrorHint(e)),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
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
          'Se borrará la tienda guardada en este dispositivo y la URL del '
          'backend que hayas configurado manualmente. '
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
      await widget.onChangeStore();
    }
  }

  void _closeApp() {
    SystemNavigator.pop();
  }

  String _dashboardAccessHint() {
    if (!widget.onlineStatus) {
      return 'Sin conexión: no se puede verificar si este equipo tiene '
          'dashboard habilitado.';
    }

    return 'El dashboard no está habilitado en este dispositivo. '
        'Tocá «Habilitar dashboard» e ingresá el PIN del servidor '
        '(DASHBOARD_ADMIN_PIN). No hace falta configurarlo en Postman: '
        'la app usa el storeId y el deviceId de abajo.';
  }

  Widget _buildDashboardAccessSection(BuildContext context) {
    if (_deviceAccessLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: LinearProgressIndicator(),
      );
    }

    final enabled = _operationalDashboardVisible;
    final mode = _deviceDashboardConfig?.deviceMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (enabled) ...[
          FilledButton.tonalIcon(
            onPressed: widget.onlineStatus
                ? () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => DashboardHomeScreen(
                          storeId: widget.storeId,
                          repository: widget.dashboardRepository,
                          shellOnline: widget.onlineStatus,
                        ),
                      ),
                    );
                  }
                : null,
            icon: const Icon(Icons.analytics_outlined),
            label: const Text('Dashboard operativo'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: PosSaleUi.primaryDim,
              foregroundColor: PosSaleUi.primary,
            ),
          ),
          const SizedBox(height: 8),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: PosSaleUi.surface3,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: PosSaleUi.border),
            ),
            child: Text(
              _dashboardAccessHint(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PosSaleUi.textMuted,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.onlineStatus)
          OutlinedButton.icon(
            onPressed: enabled
                ? () => _toggleOperationalDashboard(enable: false)
                : () => _toggleOperationalDashboard(enable: true),
            icon: Icon(enabled ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            label: Text(
              enabled ? 'Deshabilitar dashboard' : 'Habilitar dashboard',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        if (mode != null && enabled) ...[
          const SizedBox(height: 6),
          Text(
            'Modo servidor: ${mode.apiValue}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PosSaleUi.textFaint,
            ),
          ),
        ],
      ],
    );
  }

  Widget _functionalCurrencyCard(BuildContext context, BusinessSettings s) {
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
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: PosSaleUi.textMuted),
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
              padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                32 + MediaQuery.of(context).padding.bottom + 88,
              ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                _buildDashboardAccessSection(context),
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
                          localPrefs: widget.localPrefs,
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
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: widget.syncBusy || widget.onRequestSync == null
                      ? null
                      : () async {
                          await widget.onRequestSync!();
                          if (!mounted) return;
                          setState(() {
                            _future = _loadSettingsWithCache();
                          });
                        },
                  icon: widget.syncBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    widget.syncBusy ? 'Sincronizando…' : 'Sincronizar',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: PosSaleUi.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Actualiza precios, tasa de cambio y envía ventas pendientes. '
                  'No hace falta entrar al POS.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PosSaleUi.textMuted,
                    height: 1.35,
                  ),
                ),
                if (widget.cashSessionsApi != null &&
                    widget.syncApi != null &&
                    widget.catalogInvalidationBus != null) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (ctx) => CashCloseScreen(
                            storeId: widget.storeId,
                            localPrefs: widget.localPrefs,
                            cashSessionsApi: widget.cashSessionsApi!,
                            syncApi: widget.syncApi!,
                            catalogInvalidationBus:
                                widget.catalogInvalidationBus!,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.point_of_sale_outlined),
                    label: const Text('Cerrar caja'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: PosSaleUi.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Fin de turno: contar efectivo, sincronizar pendientes y '
                    'congelar el resumen. No reemplaza Sincronizar.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PosSaleUi.textMuted,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: widget.onConnectivityModeButtonPressed,
                  icon: Icon(widget.onlineStatus ? Icons.wifi_off : Icons.wifi),
                  label: Text(
                    widget.onlineStatus ? 'Poner Offline' : 'Poner Online',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    backgroundColor: widget.onlineStatus
                        ? Colors.green.withValues(alpha: 0.16)
                        : Colors.red.withValues(alpha: 0.16),
                    foregroundColor: widget.onlineStatus
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.onlineStatus
                      ? 'Estado actual: Online'
                      : 'Estado actual: Offline',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: widget.onlineStatus ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
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

/// Diálogo PIN: el [TextEditingController] vive en el [State] y se libera al cerrar el diálogo.
String _dashboardPatchErrorHint(ApiError e) {
  final msg = e.userMessageForSupport;
  if (e.statusCode == 401 ||
      msg.toLowerCase().contains('invalid') ||
      msg.toLowerCase().contains('pin') ||
      msg.toLowerCase().contains('unauthorized')) {
    return 'PIN rechazado por el servidor (${e.statusCode}). '
        'Verificá DASHBOARD_ADMIN_PIN en el `.env` del API.\n$msg';
  }
  if (e.statusCode == 404) {
    return 'Dispositivo no registrado en el servidor (${e.statusCode}). '
        'Hacé al menos una venta o sync con este equipo antes de habilitar '
        'dashboard.\n$msg';
  }
  return msg;
}

class _DashboardAdminPinDialog extends StatefulWidget {
  const _DashboardAdminPinDialog({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  State<_DashboardAdminPinDialog> createState() => _DashboardAdminPinDialogState();
}

class _DashboardAdminPinDialogState extends State<_DashboardAdminPinDialog> {
  late final TextEditingController _ctrl;
  String _err = '';
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = _ctrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _err = 'Ingresá el PIN del servidor.');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.message, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'PIN del servidor (DASHBOARD_ADMIN_PIN)',
              border: const OutlineInputBorder(),
              errorText: _err.isEmpty ? null : _err,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
