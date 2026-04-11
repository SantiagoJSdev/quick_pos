import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/models/latest_exchange_rate.dart';
import '../../core/storage/local_prefs.dart';
import 'register_exchange_rate_screen.dart';

const _kPairs = ['USD', 'VES', 'EUR'];

class ExchangeRateTodayScreen extends StatefulWidget {
  const ExchangeRateTodayScreen({
    super.key,
    required this.storeId,
    required this.exchangeRatesApi,
    required this.localPrefs,
    this.initialBase,
    this.initialQuote,
  });

  final String storeId;
  final ExchangeRatesApi exchangeRatesApi;
  final LocalPrefs localPrefs;
  final String? initialBase;
  final String? initialQuote;

  @override
  State<ExchangeRateTodayScreen> createState() =>
      _ExchangeRateTodayScreenState();
}

class _ExchangeRateTodayScreenState extends State<ExchangeRateTodayScreen> {
  late String _base;
  late String _quote;
  final _effectiveOnController = TextEditingController();
  LatestExchangeRate? _data;
  bool _loading = true;
  String? _error;
  bool _fromCache = false;

  @override
  void initState() {
    super.initState();
    _base = widget.initialBase ?? 'USD';
    _quote = widget.initialQuote ?? 'VES';
    if (_base == _quote) {
      _quote = _kPairs.firstWhere((c) => c != _base, orElse: () => 'VES');
    }
    _load();
  }

  @override
  void dispose() {
    _effectiveOnController.dispose();
    super.dispose();
  }

  Future<void> _openRegister() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => RegisterExchangeRateScreen(
          storeId: widget.storeId,
          exchangeRatesApi: widget.exchangeRatesApi,
          initialBase: _base,
          initialQuote: _quote,
        ),
      ),
    );
    if (ok == true && mounted) {
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _fromCache = false;
    });
    try {
      final effectiveOn = _effectiveOnController.text.trim();
      final data = await widget.exchangeRatesApi.getLatest(
        widget.storeId,
        baseCurrencyCode: _base,
        quoteCurrencyCode: _quote,
        effectiveOn: effectiveOn.isEmpty ? null : effectiveOn,
      );
      await widget.localPrefs.saveLatestRateCache(
        storeId: widget.storeId,
        baseCurrencyCode: _base,
        quoteCurrencyCode: _quote,
        effectiveOn: effectiveOn.isEmpty ? null : effectiveOn,
        rate: data,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
        _fromCache = false;
      });
    } on ApiError catch (e) {
      final effectiveOn = _effectiveOnController.text.trim();
      final cached = await widget.localPrefs.loadLatestRateCache(
        storeId: widget.storeId,
        baseCurrencyCode: _base,
        quoteCurrencyCode: _quote,
        effectiveOn: effectiveOn.isEmpty ? null : effectiveOn,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _data = cached;
          _error = null;
          _loading = false;
          _fromCache = true;
        });
      } else {
        setState(() {
          _data = null;
          _error = e.userMessageForSupport;
          _loading = false;
        });
      }
    } catch (e) {
      final effectiveOn = _effectiveOnController.text.trim();
      final cached = await widget.localPrefs.loadLatestRateCache(
        storeId: widget.storeId,
        baseCurrencyCode: _base,
        quoteCurrencyCode: _quote,
        effectiveOn: effectiveOn.isEmpty ? null : effectiveOn,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _data = cached;
          _error = null;
          _loading = false;
          _fromCache = true;
        });
      } else {
        setState(() {
          _data = null;
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasa del día'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_chart),
            onPressed: _loading ? null : _openRegister,
            tooltip: 'Registrar nueva tasa',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Text(
              'Referencia para la tienda',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _currencyDropdown(true)),
                const SizedBox(width: 12),
                Expanded(child: _currencyDropdown(false)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _effectiveOnController,
              decoration: const InputDecoration(
                labelText: 'Fecha de referencia (opcional)',
                hintText: 'YYYY-MM-DD — vacío = hoy en servidor',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _load(),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _load,
              child: const Text('Consultar tasa'),
            ),
            const SizedBox(height: 32),
            if (_fromCache) ...[
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
                  'Mostrando tasa cacheada (modo offline).',
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_data != null)
              _ResultCard(data: _data!),
          ],
        ),
      ),
    );
  }

  Widget _currencyDropdown(bool isBase) {
    final value = isBase ? _base : _quote;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: isBase ? 'Base' : 'Cotizada',
        border: const OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: [
            for (final c in _kPairs) DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: _loading
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() {
                    if (isBase) {
                      _base = v;
                      if (_quote == _base) {
                        _quote = _kPairs.firstWhere((c) => c != _base);
                      }
                    } else {
                      _quote = v;
                      if (_base == _quote) {
                        _base = _kPairs.firstWhere((c) => c != _quote);
                      }
                    }
                  });
                },
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.data});

  final LatestExchangeRate data;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${data.baseCurrencyCode} → ${data.quoteCurrencyCode}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            SelectableText(
              data.rateQuotePerBase,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text('Fecha efectiva: ${data.effectiveDate}'),
            if (data.convention != null && data.convention!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(data.convention!),
            ],
            if (data.source != null && data.source!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Fuente: ${data.source}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (data.notes != null && data.notes!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                data.notes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
