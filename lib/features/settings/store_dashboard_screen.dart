import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/models/business_settings.dart';
import 'exchange_rate_today_screen.dart';
import 'register_exchange_rate_screen.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({
    super.key,
    required this.storeId,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.onChangeStore,
  });

  final String storeId;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final VoidCallback onChangeStore;

  @override
  State<StoreDashboardScreen> createState() => _StoreDashboardScreenState();
}

class _StoreDashboardScreenState extends State<StoreDashboardScreen> {
  late Future<BusinessSettings> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.storesApi.getBusinessSettings(widget.storeId);
  }

  Future<void> _refresh() async {
    setState(() {
      _future = widget.storesApi.getBusinessSettings(widget.storeId);
    });
    await _future;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tienda'),
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
              msg = err.userMessage;
              if (err.requestId != null) {
                msg = '$msg\n(requestId: ${err.requestId})';
              }
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
                    Text(msg, textAlign: TextAlign.center),
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
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  s.storeName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if (s.storeType != null)
                  Text(
                    s.storeType!,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                const SizedBox(height: 24),
                _currencyCard(
                  context,
                  title: 'Moneda funcional',
                  code: s.functionalCurrency.code,
                  name: s.functionalCurrency.name,
                  help:
                      'Es la moneda en la que contabilizás inventario y costos '
                      '(valor del stock, márgenes internos). Suele ser estable, '
                      'por ejemplo USD.',
                ),
                _currencyCard(
                  context,
                  title: 'Moneda del documento (venta)',
                  code: doc?.code,
                  name: doc?.name,
                  help:
                      'Es la moneda por defecto del ticket en caja: precios y '
                      'totales que ve el cliente al cobrar (por ejemplo VES). '
                      'Puede ser distinta de la funcional: el backend guarda '
                      'ambas y la tasa del momento al confirmar la venta.',
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx) => ExchangeRateTodayScreen(
                          storeId: widget.storeId,
                          exchangeRatesApi: widget.exchangeRatesApi,
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
                const SizedBox(height: 24),
                Text(
                  'ID tienda',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  widget.storeId,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const SizedBox(height: 32),
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
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _currencyCard(
    BuildContext context, {
    required String title,
    required String? code,
    required String? name,
    required String help,
  }) {
    final value = code == null || code.isEmpty
        ? '—'
        : (name != null && name.isNotEmpty ? '$code — $name' : code);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              help,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
