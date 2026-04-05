import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';

const _kPairs = ['USD', 'VES', 'EUR'];
final _decimalPositive = RegExp(r'^\d+(\.\d+)?$');
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

String _todayIso() {
  final n = DateTime.now().toUtc();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

/// A4 — `POST /api/v1/exchange-rates` (admin en campo).
class RegisterExchangeRateScreen extends StatefulWidget {
  const RegisterExchangeRateScreen({
    super.key,
    required this.storeId,
    required this.exchangeRatesApi,
    this.initialBase,
    this.initialQuote,
  });

  final String storeId;
  final ExchangeRatesApi exchangeRatesApi;
  final String? initialBase;
  final String? initialQuote;

  @override
  State<RegisterExchangeRateScreen> createState() =>
      _RegisterExchangeRateScreenState();
}

class _RegisterExchangeRateScreenState
    extends State<RegisterExchangeRateScreen> {
  late String _base;
  late String _quote;
  final _rateController = TextEditingController();
  final _effectiveDateController = TextEditingController();
  final _sourceController = TextEditingController(text: 'MANUAL');
  final _notesController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _base = widget.initialBase ?? 'USD';
    _quote = widget.initialQuote ?? 'VES';
    if (!_kPairs.contains(_base)) _base = 'USD';
    if (!_kPairs.contains(_quote)) _quote = 'VES';
    if (_base == _quote) {
      _quote = _kPairs.firstWhere((c) => c != _base, orElse: () => 'VES');
    }
    _effectiveDateController.text = _todayIso();
  }

  @override
  void dispose() {
    _rateController.dispose();
    _effectiveDateController.dispose();
    _sourceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final rate = _rateController.text.trim();
    final date = _effectiveDateController.text.trim();
    final source = _sourceController.text.trim();

    if (rate.isEmpty || !_decimalPositive.hasMatch(rate)) {
      setState(() => _error = 'Indica la tasa como número decimal (ej. 36.50).');
      return;
    }
    if (!_isoDate.hasMatch(date)) {
      setState(() => _error = 'Fecha efectiva: formato YYYY-MM-DD.');
      return;
    }
    if (_base == _quote) {
      setState(() => _error = 'Base y cotizada deben ser distintas.');
      return;
    }
    if (source.isEmpty) {
      setState(() => _error = 'Indica una fuente (ej. MANUAL, BCV).');
      return;
    }

    setState(() => _loading = true);
    try {
      await widget.exchangeRatesApi.createRate(
        widget.storeId,
        baseCurrencyCode: _base,
        quoteCurrencyCode: _quote,
        rateQuotePerBase: rate,
        effectiveDate: date,
        source: source,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tasa registrada')),
      );
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      final msg = e.userMessageForSupport;
      setState(() => _error = msg);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar tasa'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Alta manual de tasa (append-only en servidor). '
            'Requiere par de monedas existente en la tienda.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _dropdown(true)),
              const SizedBox(width: 12),
              Expanded(child: _dropdown(false)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _rateController,
            decoration: const InputDecoration(
              labelText: 'Tasa (1 base = ? cotizada)',
              hintText: '36.50',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_loading,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _effectiveDateController,
            decoration: const InputDecoration(
              labelText: 'Fecha efectiva (YYYY-MM-DD)',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sourceController,
            decoration: const InputDecoration(
              labelText: 'Fuente',
              hintText: 'MANUAL, BCV, …',
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notas (opcional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            enabled: !_loading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar tasa'),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(bool isBase) {
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
