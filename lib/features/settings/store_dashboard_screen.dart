import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/stores_api.dart';
import '../../core/models/business_settings.dart';

class StoreDashboardScreen extends StatefulWidget {
  const StoreDashboardScreen({
    super.key,
    required this.storeId,
    required this.storesApi,
    required this.onChangeStore,
  });

  final String storeId;
  final StoresApi storesApi;
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
            onPressed: widget.onChangeStore,
            child: const Text('Cambiar tienda'),
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
                _tile(
                  context,
                  title: 'Moneda funcional',
                  subtitle:
                      '${s.functionalCurrency.code}${s.functionalCurrency.name != null ? ' — ${s.functionalCurrency.name}' : ''}',
                ),
                _tile(
                  context,
                  title: 'Moneda documento por defecto',
                  subtitle: doc != null
                      ? '${doc.code}${doc.name != null ? ' — ${doc.name}' : ''}'
                      : '—',
                ),
                const SizedBox(height: 32),
                Text(
                  'API: ${widget.storeId}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }
}
