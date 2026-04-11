import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/storage/local_prefs.dart';
import 'create_store_screen.dart';

final _uuidLike = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

class LinkStoreScreen extends StatefulWidget {
  const LinkStoreScreen({
    super.key,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.onLinked,
    required this.localPrefs,
    this.initialStoreId,
  });

  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final Future<void> Function(String storeId) onLinked;
  final LocalPrefs localPrefs;
  final String? initialStoreId;

  @override
  State<LinkStoreScreen> createState() => _LinkStoreScreenState();
}

class _LinkStoreScreenState extends State<LinkStoreScreen> {
  late final TextEditingController _controller;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialStoreId ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final raw = _controller.text.trim();
    setState(() {
      _error = null;
    });
    if (!_uuidLike.hasMatch(raw)) {
      setState(() {
        _error = 'Introduce un UUID de tienda válido.';
      });
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.storesApi.getBusinessSettings(raw);
      if (!mounted) return;
      await widget.onLinked(raw);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo conectar: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateStore() async {
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => CreateStoreScreen(
          storesApi: widget.storesApi,
          exchangeRatesApi: widget.exchangeRatesApi,
        ),
      ),
    );
    if (!mounted || id == null) return;
    await widget.onLinked(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick POS')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enlazar tienda',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Pega el UUID de la tienda. Se validará con el servidor '
                '(business-settings). La URL del API es la de compilación o la '
                'que guardaste en Configuración (clave).',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'UUID de tienda (X-Store-Id)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text,
                autocorrect: false,
                enabled: !_loading,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _connect,
                child: _loading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Conectar'),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loading ? null : _openCreateStore,
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Crear tienda nueva (UUID en este equipo)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
