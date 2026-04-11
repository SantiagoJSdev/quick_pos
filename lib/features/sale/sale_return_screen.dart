import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/sale_returns_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/recent_sale_ticket.dart';
import '../../core/network/network_errors.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_sale_return_entry.dart';
import '../../core/sync/sale_return_payload.dart';
import '../../core/sync/sync_cycle.dart';
import '../shell/shell_online_scope.dart';
import 'pos_sale_ui_tokens.dart';

final _decimalPositive = RegExp(r'^\d+(\.\d+)?$');

class _ParsedSaleLine {
  _ParsedSaleLine({
    required this.saleLineId,
    required this.productId,
    required this.label,
    required this.quantitySold,
  });

  final String saleLineId;
  final String productId;
  final String label;
  final String quantitySold;
}

List<_ParsedSaleLine> _parseSaleLines(Map<String, dynamic> sale) {
  final raw = sale['saleLines'] ?? sale['lines'];
  if (raw is! List) return [];
  final out = <_ParsedSaleLine>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    final id = m['id']?.toString();
    if (id == null || id.isEmpty) continue;
    final pid = m['productId']?.toString() ?? '';
    var label = pid;
    final prod = m['product'];
    if (prod is Map) {
      final name = prod['name']?.toString();
      final sku = prod['sku']?.toString();
      if (name != null && name.isNotEmpty) label = name;
      if (sku != null && sku.isNotEmpty) {
        label = label.isEmpty ? sku : '$label · $sku';
      }
    }
    final qty = m['quantity']?.toString() ?? '0';
    out.add(
      _ParsedSaleLine(
        saleLineId: id,
        productId: pid,
        label: label.isEmpty ? id.substring(0, 8) : label,
        quantitySold: qty,
      ),
    );
  }
  return out;
}

class _QtyRow {
  _QtyRow(this.line) : controller = TextEditingController();

  final _ParsedSaleLine line;
  final TextEditingController controller;

  void dispose() => controller.dispose();
}

/// `POST /sale-returns` o cola `SALE_RETURN` si no hay red (`SYNC_CONTRACTS.md`).
class SaleReturnScreen extends StatefulWidget {
  const SaleReturnScreen({
    super.key,
    required this.storeId,
    required this.salesApi,
    required this.saleReturnsApi,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.localPrefs,
    required this.syncApi,
    required this.catalogInvalidationBus,
  });

  final String storeId;
  final SalesApi salesApi;
  final SaleReturnsApi saleReturnsApi;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final LocalPrefs localPrefs;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;

  @override
  State<SaleReturnScreen> createState() => _SaleReturnScreenState();
}

class _SaleReturnScreenState extends State<SaleReturnScreen> {
  final _saleIdController = TextEditingController();
  BusinessSettings? _settings;
  Map<String, dynamic>? _loadedSale;
  List<_QtyRow> _rows = [];
  bool _loadingSale = false;
  bool _submitting = false;
  String? _error;
  String? _fxLoadError;
  SaleFxPair? _fxPair;
  bool _useSpotFx = false;
  String? _clientReturnId;
  PosTerminalInfo? _terminal;
  bool _shellOnline = true;
  bool? _shellOnlineBound;

  @override
  void initState() {
    super.initState();
    PosTerminalInfo.load(widget.localPrefs).then((t) {
      if (mounted) setState(() => _terminal = t);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ShellOnlineScope.of(context);
    if (_shellOnlineBound == next) return;
    _shellOnlineBound = next;
    _shellOnline = next;
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _saleIdController.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!_shellOnline) {
      final cached = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _settings = cached;
          _error = null;
        });
      } else {
        setState(() {
          _settings = null;
          _error =
              'Sin configuración en caché. Conectate para usar devoluciones.';
        });
      }
      return;
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
      if (mounted) setState(() => _settings = s);
    } on ApiError catch (e) {
      final cached = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() => _settings = cached);
      } else {
        setState(() => _error = e.userMessageForSupport);
      }
    } catch (e) {
      final cached = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() => _settings = cached);
      } else {
        setState(() => _error = e.toString());
      }
    }
  }

  String get _functionalCode => _settings?.functionalCurrency.code ?? '';

  String? get _documentFromSale =>
      _loadedSale?['documentCurrencyCode']?.toString();

  Future<SaleFxPair?> _fetchFxPair(String func, String doc) async {
    try {
      final r = await widget.exchangeRatesApi.getLatest(
        widget.storeId,
        baseCurrencyCode: func,
        quoteCurrencyCode: doc,
      );
      return SaleFxPair(rate: r, inverted: false);
    } on ApiError catch (e) {
      if (e.statusCode != 404) rethrow;
      try {
        final r2 = await widget.exchangeRatesApi.getLatest(
          widget.storeId,
          baseCurrencyCode: doc,
          quoteCurrencyCode: func,
        );
        return SaleFxPair(rate: r2, inverted: true);
      } on ApiError catch (e2) {
        if (e2.statusCode == 404) return null;
        rethrow;
      }
    }
  }

  Future<void> _refreshFxIfNeeded() async {
    final func = _functionalCode;
    final doc = _documentFromSale ?? _settings?.defaultSaleDocCurrency?.code;
    if (func.isEmpty || doc == null || doc.isEmpty) {
      setState(() {
        _fxPair = null;
        _fxLoadError = null;
      });
      return;
    }
    if (func.toUpperCase() == doc.toUpperCase()) {
      setState(() {
        _fxPair = null;
        _fxLoadError = null;
      });
      return;
    }
    setState(() => _fxLoadError = null);
    try {
      final pair = await _fetchFxPair(func, doc);
      if (pair != null) {
        await widget.localPrefs.savePosFxPairCache(
          storeId: widget.storeId,
          functionalCode: func,
          documentCode: doc,
          pair: pair,
        );
      }
      if (mounted) {
        setState(() {
          _fxPair = pair;
          _fxLoadError = pair == null
              ? 'No hay tasa del día para $func/$doc.'
              : null;
        });
      }
    } catch (e) {
      final cached = await widget.localPrefs.loadPosFxPairCache(
        storeId: widget.storeId,
        functionalCode: func,
        documentCode: doc,
      );
      if (!mounted) return;
      if (cached != null) {
        setState(() {
          _fxPair = cached;
          _fxLoadError = null;
        });
      } else {
        setState(() {
          _fxPair = null;
          _fxLoadError = e.toString();
        });
      }
    }
  }

  Future<void> _loadSale() async {
    var id = _saleIdController.text.trim();
    if (id.isEmpty) {
      setState(
        () => _error =
            'Ingresá el número de ticket (historial de hoy) o el UUID de la venta.',
      );
      return;
    }
    if (RegExp(r'^\d{1,5}$').hasMatch(id)) {
      final hit = await widget.localPrefs.findRecentSaleTicketByDisplayCode(
        widget.storeId,
        id,
      );
      if (!mounted) return;
      if (hit == null) {
        setState(() {
          _error =
              'No hay ticket con ese número en «Este dispositivo» para hoy. '
              'Revisá Ventas → Historial o usá el UUID desde la pestaña General.';
        });
        return;
      }
      if (hit.status == RecentSaleTicket.statusQueued) {
        setState(() {
          _error =
              'Ese ticket aún no llegó al servidor. Esperá la sincronización automática '
              'y volvé a intentar, o usá el UUID si ya figura en General.';
        });
        return;
      }
      id = hit.saleId;
    }
    setState(() {
      _loadingSale = true;
      _error = null;
      for (final r in _rows) {
        r.dispose();
      }
      _rows = [];
      _loadedSale = null;
    });
    try {
      final json = await widget.salesApi.getSale(widget.storeId, id);
      final lines = _parseSaleLines(json);
      if (lines.isEmpty) {
        if (mounted) {
          setState(() {
            _loadingSale = false;
            _error = 'La venta no tiene líneas con id (saleLines).';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _loadedSale = json;
        _rows = lines.map(_QtyRow.new).toList();
        _loadingSale = false;
      });
      if (_useSpotFx) await _refreshFxIfNeeded();
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _loadingSale = false;
          _error = e.userMessageForSupport;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSale = false;
          _error = e.toString();
        });
      }
    }
  }

  bool _quantityOk(String returnQty, String sold) {
    if (!_decimalPositive.hasMatch(returnQty)) return false;
    final a = double.tryParse(returnQty);
    final b = double.tryParse(sold);
    if (a == null || b == null || a <= 0 || a > b + 1e-9) return false;
    return true;
  }

  Future<void> _submit() async {
    final sale = _loadedSale;
    if (sale == null) {
      setState(() => _error = 'Primero cargá la venta.');
      return;
    }
    final originalSaleId =
        sale['id']?.toString() ?? _saleIdController.text.trim();
    if (originalSaleId.isEmpty) {
      setState(() => _error = 'Venta sin id.');
      return;
    }

    final linePayload = <Map<String, dynamic>>[];
    final productIds = <String>{};
    for (final r in _rows) {
      final q = r.controller.text.trim();
      if (q.isEmpty) continue;
      if (!_quantityOk(q, r.line.quantitySold)) {
        setState(
          () => _error =
              'Cantidad inválida en "${r.line.label}" (máx. vendido: ${r.line.quantitySold}).',
        );
        return;
      }
      linePayload.add(
        SaleReturnPayload.lineRow(saleLineId: r.line.saleLineId, quantity: q),
      );
      if (r.line.productId.isNotEmpty) productIds.add(r.line.productId);
    }
    if (linePayload.isEmpty) {
      setState(() => _error = 'Indicá al menos una cantidad a devolver.');
      return;
    }

    final func = _functionalCode;
    final doc =
        _documentFromSale ?? _settings?.defaultSaleDocCurrency?.code ?? '';
    if (func.isEmpty || doc.isEmpty) {
      setState(() => _error = 'Falta configuración de monedas de la tienda.');
      return;
    }

    final fxPolicy = _useSpotFx
        ? SaleReturnPayload.fxPolicySpot
        : SaleReturnPayload.fxPolicyInherit;
    Map<String, dynamic>? fxSnap;
    if (_useSpotFx) {
      if (func.toUpperCase() != doc.toUpperCase() && _fxPair == null) {
        setState(() {
          _error =
              _fxLoadError ??
              'Con tasa al momento necesitás la tasa del día funcional→documento.';
        });
        return;
      }
      fxSnap = SaleReturnPayload.buildFxSnapshot(
        functionalCurrencyCode: func,
        documentCurrencyCode: doc,
        fxPair: _fxPair,
      );
    }

    _clientReturnId ??= ClientMutationId.newId();
    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;

    final restFx = fxSnap == null
        ? null
        : (Map<String, dynamic>.from(fxSnap)..remove('fxSource'));
    final restBody = SaleReturnPayload.toRestBody(
      originalSaleId: originalSaleId,
      lines: linePayload,
      clientReturnId: _clientReturnId,
      fxPolicy: fxPolicy,
      fxSnapshot: restFx,
    );

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.saleReturnsApi.createSaleReturn(widget.storeId, restBody);
      if (!mounted) return;
      widget.catalogInvalidationBus.invalidateFromLocalMutation(
        productIds: productIds,
      );
      unawaited(
        runSyncCycle(
          storeId: widget.storeId,
          prefs: widget.localPrefs,
          syncApi: widget.syncApi,
          deviceId: _terminal!.deviceId,
          appVersion: _terminal!.appVersion,
          catalogInvalidation: widget.catalogInvalidationBus,
          doPull: false,
          doFlush: true,
        ),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Devolución registrada.')));
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.userMessageForSupport);
    } catch (e) {
      if (!mounted) return;
      if (isLikelyNetworkFailure(e)) {
        final syncOpId = ClientMutationId.newId();
        final syncObj = SaleReturnPayload.toSyncSaleReturnObject(
          storeId: widget.storeId,
          originalSaleId: originalSaleId,
          lines: linePayload,
          clientReturnId: _clientReturnId,
          fxPolicy: fxPolicy,
          fxSnapshot: fxSnap,
          fxSourceOffline: 'POS_OFFLINE',
        );
        await widget.localPrefs.appendPendingSaleReturn(
          PendingSaleReturnEntry(
            opId: syncOpId,
            storeId: widget.storeId,
            saleReturn: syncObj,
            opTimestampIso: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        if (!mounted) return;
        widget.catalogInvalidationBus.invalidateFromLocalMutation(
          productIds: productIds,
        );
        unawaited(
          runSyncCycle(
            storeId: widget.storeId,
            prefs: widget.localPrefs,
            syncApi: widget.syncApi,
            deviceId: _terminal!.deviceId,
            appVersion: _terminal!.appVersion,
            catalogInvalidation: widget.catalogInvalidationBus,
            doPull: false,
            doFlush: true,
          ),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión: devolución en cola. Se enviará con sync/push.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docLabel = _documentFromSale ?? '—';
    return Scaffold(
      appBar: AppBar(title: const Text('Devolución de venta')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Podés usar el número corto del ticket (Ventas → Historial → Este dispositivo, '
            'ventas de hoy) o pegar el UUID del servidor (pestaña General del historial o detalle). '
            'Luego indicá cantidades a devolver. FX: por defecto se hereda de la venta; opcional SPOT.',
            style: TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _saleIdController,
            style: const TextStyle(color: PosSaleUi.text),
            decoration: const InputDecoration(
              labelText: 'Nº ticket (hoy) o UUID de la venta',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _loadingSale ? null : _loadSale,
            child: _loadingSale
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cargar venta'),
          ),
          if (_loadedSale != null) ...[
            const SizedBox(height: 16),
            Text(
              'Moneda documento venta: $docLabel',
              style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 12),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Tasa al momento (SPOT_ON_RETURN)',
                style: TextStyle(color: PosSaleUi.text, fontSize: 14),
              ),
              subtitle: const Text(
                'Si no, se hereda FX de la venta original.',
                style: TextStyle(color: PosSaleUi.textFaint, fontSize: 11),
              ),
              value: _useSpotFx,
              onChanged: _loadingSale
                  ? null
                  : (v) async {
                      setState(() => _useSpotFx = v);
                      if (v && _loadedSale != null) await _refreshFxIfNeeded();
                    },
              activeThumbColor: PosSaleUi.primary,
            ),
            if (_useSpotFx && _fxLoadError != null)
              Text(
                _fxLoadError!,
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Cantidad a devolver (vacío = no devolver esa línea)',
              style: TextStyle(
                color: PosSaleUi.text,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            ..._rows.map((r) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      r.line.label,
                      style: const TextStyle(
                        color: PosSaleUi.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Vendido: ${r.line.quantitySold}',
                      style: const TextStyle(
                        color: PosSaleUi.textFaint,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: r.controller,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(color: PosSaleUi.text),
                      decoration: const InputDecoration(
                        hintText: 'Cantidad a devolver',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Confirmar devolución'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
          ],
        ],
      ),
    );
  }
}
