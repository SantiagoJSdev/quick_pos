import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/cash/cash_session_service.dart';
import '../../core/api/cash_sessions_api.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/cash_session.dart';
import '../../core/pos/money_string_math.dart';
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/device_hydrate_sync.dart';
import '../shell/shell_online_scope.dart';
import 'pos_sale_ui_tokens.dart';

/// Pantalla obligatoria antes del POS: contar fondo de apertura.
///
/// El cajero elige moneda principal (funcional, ej. USD) o bolívares (VES).
/// Internamente siempre se guarda/envía [openingCash] en moneda funcional.
class CashOpenScreen extends StatefulWidget {
  const CashOpenScreen({
    super.key,
    required this.storeId,
    required this.localPrefs,
    required this.cashSessionsApi,
    this.onHydrateDevice,
  });

  final String storeId;
  final LocalPrefs localPrefs;
  final CashSessionsApi cashSessionsApi;
  final DeviceHydrateCallback? onHydrateDevice;

  @override
  State<CashOpenScreen> createState() => _CashOpenScreenState();
}

class _CashOpenScreenState extends State<CashOpenScreen> {
  final _amountCtrl = TextEditingController();
  late final CashSessionService _service;

  bool _loading = true;
  bool _busy = false;
  String? _hydrateStep;
  String? _error;
  String? _lastHydratedLabel;

  BusinessSettings? _settings;
  SaleFxPair? _fxPair;
  /// `functional` | `document` (VES típico).
  String _inputCurrencyMode = 'functional';

  @override
  void initState() {
    super.initState();
    _service = CashSessionService(
      prefs: widget.localPrefs,
      api: widget.cashSessionsApi,
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  String get _functionalCode =>
      _settings?.functionalCurrency.code.trim().toUpperCase() ?? 'USD';

  String get _documentCode {
    final d = _settings?.defaultSaleDocCurrency?.code.trim().toUpperCase();
    if (d == null || d.isEmpty) return _functionalCode;
    return d;
  }

  bool get _hasDualCurrency =>
      _functionalCode.isNotEmpty &&
      _documentCode.isNotEmpty &&
      _functionalCode != _documentCode;

  String get _inputCurrencyCode =>
      _inputCurrencyMode == 'document' ? _documentCode : _functionalCode;

  /// Monto en funcional a enviar (convierte si eligió Bs).
  String? get _openingCashFunctional {
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty || double.tryParse(raw) == null) return null;
    if (_inputCurrencyMode == 'functional' || !_hasDualCurrency) {
      return double.parse(raw).toStringAsFixed(2);
    }
    if (_fxPair == null) return null;
    final rate = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: _functionalCode,
      documentCode: _documentCode,
      pair: _fxPair,
    );
    return MoneyStringMath.divide(raw, rate, fractionDigits: 2);
  }

  String? get _convertedPreview {
    if (!_hasDualCurrency || _inputCurrencyMode != 'document') return null;
    final f = _openingCashFunctional;
    if (f == null) return null;
    return '≈ $f $_functionalCode';
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final existing = await _service.loadOpenSession(widget.storeId);
      if (existing != null &&
          !LocalCashSession.isZeroOpeningCash(existing.openingCash)) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
        return;
      }

      final settings = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      SaleFxPair? pair;
      if (settings != null) {
        final func = settings.functionalCurrency.code;
        final doc =
            settings.defaultSaleDocCurrency?.code ?? func;
        if (func.toUpperCase() != doc.toUpperCase()) {
          pair = await widget.localPrefs.loadPosFxPairCache(
            storeId: widget.storeId,
            functionalCode: func,
            documentCode: doc,
          );
        }
      }

      final lastSync = await widget.localPrefs.loadLastSuccessfulSyncAt();
      String? hydratedLabel;
      if (lastSync != null) {
        final local = lastSync.toLocal();
        hydratedLabel =
            '${local.day.toString().padLeft(2, '0')}/'
            '${local.month.toString().padLeft(2, '0')} '
            '${local.hour.toString().padLeft(2, '0')}:'
            '${local.minute.toString().padLeft(2, '0')}';
      }

      if (!mounted) return;
      setState(() {
        _settings = settings;
        _fxPair = pair;
        _lastHydratedLabel = hydratedLabel;
        _loading = false;
        if (settings == null) {
          _error =
              'Sin configuración de tienda en este teléfono. '
              'Sincronizá desde Inicio cuando haya red.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _confirmOpen() async {
    final online = ShellOnlineScope.of(context);
    final amount = _openingCashFunctional;
    if (amount == null) {
      final msg = _inputCurrencyMode == 'document' && _fxPair == null
          ? 'No hay tasa $_functionalCode→$_documentCode. '
              'Sincronizá o abrí en $_functionalCode.'
          : 'Ingresá el efectivo de apertura.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final catalog = await widget.localPrefs.loadCatalogProductsCache();
    if (!mounted) return;
    if (catalog.isEmpty && !online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este teléfono nunca bajó productos. Conectate y sincronizá una vez.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _busy = true;
      _hydrateStep = online ? 'Actualizando datos…' : 'Abriendo turno…';
      _error = null;
    });

    try {
      if (online) {
        final hydrate = widget.onHydrateDevice;
        if (hydrate != null) {
          final result = await hydrate(
            onProgress: (s) {
              if (mounted) setState(() => _hydrateStep = s);
            },
            requireEmptyQueue: false,
          );
          // Recargar tasa por si hydrate la actualizó.
          final settings =
              await widget.localPrefs.loadBusinessSettingsCache(widget.storeId);
          if (settings != null && mounted) {
            final func = settings.functionalCurrency.code;
            final doc = settings.defaultSaleDocCurrency?.code ?? func;
            final pair = func.toUpperCase() == doc.toUpperCase()
                ? null
                : await widget.localPrefs.loadPosFxPairCache(
                    storeId: widget.storeId,
                    functionalCode: func,
                    documentCode: doc,
                  );
            setState(() {
              _settings = settings;
              _fxPair = pair;
            });
          }
          if (!result.downloadedOk && catalog.isEmpty) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result.userMessage.isNotEmpty
                      ? result.userMessage
                      : 'No se pudieron bajar productos. Reintentá.',
                ),
              ),
            );
            return;
          }
        }
        setState(() => _hydrateStep = 'Registrando apertura…');
      }

      final open = await _service.openCountedSession(
        storeId: widget.storeId,
        online: online,
        openingCashFunctional: amount,
      );
      if (!mounted) return;
      if (!open.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(open.message)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(open.message)),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al abrir caja: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _hydrateStep = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ShellOnlineScope.of(context);
    return Scaffold(
      backgroundColor: PosSaleUi.bg,
      appBar: AppBar(
        backgroundColor: PosSaleUi.bg,
        foregroundColor: PosSaleUi.text,
        title: const Text('Abrir caja'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PosSaleUi.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PosSaleUi.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        online ? 'Online' : 'Sin red — apertura local',
                        style: TextStyle(
                          color: online ? Colors.greenAccent : Colors.orangeAccent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _lastHydratedLabel == null
                            ? 'Datos locales: nunca sincronizados'
                            : 'Última sync: $_lastHydratedLabel',
                        style: const TextStyle(
                          color: PosSaleUi.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      if (!online) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Vas a vender con el catálogo guardado en este teléfono. '
                          'Al volver la red, sincronizá.',
                          style: TextStyle(
                            color: PosSaleUi.textFaint,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Efectivo de apertura',
                  style: TextStyle(
                    color: PosSaleUi.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contá el efectivo con el que iniciás el turno. '
                  'Se registra en la moneda principal de la tienda.',
                  style: TextStyle(
                    color: PosSaleUi.textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (_hasDualCurrency) ...[
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'functional',
                        label: Text(_functionalCode),
                      ),
                      ButtonSegment(
                        value: 'document',
                        label: Text(_documentCode),
                      ),
                    ],
                    selected: {_inputCurrencyMode},
                    onSelectionChanged: _busy
                        ? null
                        : (s) {
                            setState(() => _inputCurrencyMode = s.first);
                          },
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _amountCtrl,
                  enabled: !_busy && _settings != null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(
                    color: PosSaleUi.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Monto ($_inputCurrencyCode)',
                    labelStyle: const TextStyle(color: PosSaleUi.textMuted),
                    hintText: '0.00',
                    filled: true,
                    fillColor: PosSaleUi.surface3,
                    helperText: _convertedPreview,
                    helperStyle: const TextStyle(color: PosSaleUi.primary),
                  ),
                ),
                if (_inputCurrencyMode == 'document' &&
                    _hasDualCurrency &&
                    _fxPair == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Sin tasa en caché. Abrí en $_functionalCode o sincronizá primero.',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _busy || _settings == null ? null : _confirmOpen,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_open_outlined),
                  label: Text(
                    _hydrateStep ??
                        (_busy ? 'Abriendo…' : 'Abrir turno'),
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: PosSaleUi.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
    );
  }
}
