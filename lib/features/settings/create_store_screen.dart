import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/stores_api.dart';

const _kCurrencyCodes = ['USD', 'VES', 'EUR'];
const _kStoreTypes = [
  ('main', 'Principal'),
  ('branch', 'Sucursal'),
];

final _decimalPositive = RegExp(r'^\d+(\.\d+)?$');

String _isoDateUtc(DateTime d) {
  final u = d.toUtc();
  final y = u.year.toString().padLeft(4, '0');
  final m = u.month.toString().padLeft(2, '0');
  final day = u.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

class CreateStoreScreen extends StatefulWidget {
  const CreateStoreScreen({
    super.key,
    required this.storesApi,
    required this.exchangeRatesApi,
  });

  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;

  @override
  State<CreateStoreScreen> createState() => _CreateStoreScreenState();
}

class _CreateStoreScreenState extends State<CreateStoreScreen> {
  static const _uuidGen = Uuid();
  late String _storeId;
  final _nameController = TextEditingController();
  String _functional = 'USD';
  String _document = 'VES';
  String _storeType = 'main';
  bool _registerInitialRate = false;
  final _rateController = TextEditingController();
  final _effectiveDateController = TextEditingController();
  String _rateBase = 'USD';
  String _rateQuote = 'VES';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _storeId = _uuidGen.v4();
    _effectiveDateController.text = _isoDateUtc(DateTime.now());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    _effectiveDateController.dispose();
    super.dispose();
  }

  void _regenerateId() {
    setState(() {
      _storeId = _uuidGen.v4();
      _error = null;
    });
  }

  Future<void> _copyId() async {
    await Clipboard.setData(ClipboardData(text: _storeId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('UUID copiado al portapapeles')),
    );
  }

  bool _validateOptionalRate() {
    if (!_registerInitialRate) return true;
    if (_rateBase == _rateQuote) {
      setState(() {
        _error = 'En la tasa inicial, base y cotizada deben ser distintas.';
      });
      return false;
    }
    final r = _rateController.text.trim();
    if (r.isEmpty || !_decimalPositive.hasMatch(r)) {
      setState(() {
        _error = 'Tasa inicial: indica un número decimal positivo (ej. 36.50).';
      });
      return false;
    }
    final d = _effectiveDateController.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(d)) {
      setState(() {
        _error = 'Fecha efectiva: formato YYYY-MM-DD.';
      });
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    setState(() => _error = null);
    if (name.isEmpty) {
      setState(() => _error = 'Indica un nombre para la tienda.');
      return;
    }
    if (!_validateOptionalRate()) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar creación'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tienda: $name'),
              Text(
                'Tipo: ${_kStoreTypes.firstWhere((e) => e.$1 == _storeType).$2} ($_storeType)',
              ),
              Text('UUID: $_storeId'),
              const SizedBox(height: 8),
              Text('Moneda funcional: $_functional'),
              Text('Moneda documento por defecto: $_document'),
              if (_registerInitialRate) ...[
                const SizedBox(height: 8),
                Text(
                  'Tasa inicial: 1 $_rateBase = ${_rateController.text.trim()} $_rateQuote '
                  '(${_effectiveDateController.text.trim()})',
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Requiere STORE_ONBOARDING_ENABLED=1 en el servidor y los PUT '
                'documentados (docs/BACKEND_STORE_ONBOARDING.md).',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;

    setState(() => _loading = true);
    try {
      await widget.storesApi.registerNewStore(
        storeId: _storeId,
        name: name,
        functionalCurrencyCode: _functional,
        defaultSaleDocCurrencyCode: _document,
        type: _storeType,
      );

      if (_registerInitialRate) {
        try {
          await widget.exchangeRatesApi.createRate(
            _storeId,
            baseCurrencyCode: _rateBase,
            quoteCurrencyCode: _rateQuote,
            rateQuotePerBase: _rateController.text.trim(),
            effectiveDate: _effectiveDateController.text.trim(),
            source: 'MANUAL',
            notes: 'Alta tienda desde POS',
          );
        } on ApiError catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Tienda creada, pero falló la tasa inicial: ${e.userMessage}',
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(_storeId);
    } on ApiError catch (e) {
      if (!mounted) return;
      var msg = e.userMessage;
      if (e.requestId != null) {
        msg = '$msg\n(requestId: ${e.requestId})';
      }
      if (e.statusCode == 403) {
        msg =
            '$msg\n\nOnboarding desactivado en servidor: definid '
            'STORE_ONBOARDING_ENABLED=1 (o true) en .env y reiniciad.';
      }
      setState(() {
        _error = '$msg\n\nContrato: docs/BACKEND_STORE_ONBOARDING.md · §13.0 FRONTEND_INTEGRATION_CONTEXT.md';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo crear: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear tienda'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _loading ? null : () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Nueva tienda',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Se genera un UUID en este dispositivo. El mismo valor se usa '
              'como recurso en el servidor y en la cabecera X-Store-Id.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 20),
            Text(
              'UUID de la tienda',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    _storeId,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Copiar',
                  onPressed: _loading ? null : _copyId,
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  tooltip: 'Generar otro UUID',
                  onPressed: _loading ? null : _regenerateId,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de la tienda',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              enabled: !_loading,
            ),
            const SizedBox(height: 20),
            Text(
              'Tipo de sucursal',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _storeType,
                  isExpanded: true,
                  items: [
                    for (final t in _kStoreTypes)
                      DropdownMenuItem(value: t.$1, child: Text(t.$2)),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) {
                          if (v != null) setState(() => _storeType = v);
                        },
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Moneda funcional',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _functional,
                  isExpanded: true,
                  items: [
                    for (final c in _kCurrencyCodes)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) {
                          if (v != null) setState(() => _functional = v);
                        },
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Moneda documento por defecto (ventas)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            InputDecorator(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _document,
                  isExpanded: true,
                  items: [
                    for (final c in _kCurrencyCodes)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) {
                          if (v != null) setState(() => _document = v);
                        },
                ),
              ),
            ),
            const SizedBox(height: 24),
            SwitchListTile(
              title: const Text('Registrar primera tasa de cambio'),
              subtitle: const Text(
                'Opcional. Usa POST /exchange-rates (misma tienda) después de crear la tienda.',
              ),
              value: _registerInitialRate,
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _registerInitialRate = v),
            ),
            if (_registerInitialRate) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Base',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _rateBase,
                          isExpanded: true,
                          items: [
                            for (final c in _kCurrencyCodes)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: _loading
                              ? null
                              : (v) {
                                  if (v != null) setState(() => _rateBase = v);
                                },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Cotizada',
                        border: OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _rateQuote,
                          isExpanded: true,
                          items: [
                            for (final c in _kCurrencyCodes)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: _loading
                              ? null
                              : (v) {
                                  if (v != null) setState(() => _rateQuote = v);
                                },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _rateController,
                decoration: const InputDecoration(
                  labelText: 'Tasa (1 base = ? cotizada)',
                  hintText: '36.50',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !_loading,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _effectiveDateController,
                decoration: const InputDecoration(
                  labelText: 'Fecha efectiva (YYYY-MM-DD)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_loading,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 20),
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
                  : const Text('Revisar y crear en servidor'),
            ),
          ],
        ),
      ),
    );
  }
}
