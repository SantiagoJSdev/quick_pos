import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/network/network_errors.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/pos_cart_line.dart';
import '../../core/pos/money_string_math.dart';
import '../../core/pos/pos_sale_pricing.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_sale_entry.dart';
import '../../core/sync/sync_cycle.dart';
import 'barcode_scanner_screen.dart';

CatalogProduct? _findByBarcode(List<CatalogProduct> products, String raw) {
  final c = raw.trim().toLowerCase();
  if (c.isEmpty) return null;
  for (final p in products) {
    final b = p.barcode?.trim().toLowerCase();
    if (b != null && b.isNotEmpty && b == c) return p;
  }
  return null;
}

/// Catálogo de venta (P1–P3), cola `sync/push` (ventas + ajustes) y sync manual.
class PosSaleScreen extends StatefulWidget {
  const PosSaleScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.salesApi,
    required this.syncApi,
    required this.localPrefs,
  });

  final String storeId;
  final ProductsApi productsApi;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final SalesApi salesApi;
  final SyncApi syncApi;
  final LocalPrefs localPrefs;

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen> {
  final _search = TextEditingController();
  List<CatalogProduct> _all = [];
  final List<PosCartLine> _cart = [];
  bool _loading = true;
  String? _error;

  BusinessSettings? _settings;
  String? _contextError;
  String? _fxLoadError;
  SaleFxPair? _fxPair;
  String? _selectedDocumentCurrency;

  PosTerminalInfo? _terminal;
  String? _pendingSaleId;
  bool _checkoutBusy = false;

  int _pendingSyncCount = 0;
  bool _flushBusy = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
    PosTerminalInfo.load(widget.localPrefs).then((t) {
      if (mounted) setState(() => _terminal = t);
    });
    _refreshPendingCount();
  }

  Future<void> _refreshPendingCount() async {
    final n =
        await widget.localPrefs.countPendingSyncOpsForStore(widget.storeId);
    if (mounted) setState(() => _pendingSyncCount = n);
  }

  /// [doPull]: actualiza watermark con `GET /sync/pull`; [doFlush]: envía cola mixta.
  Future<void> _runSyncCycle({
    bool silent = false,
    bool doPull = true,
  }) async {
    if (_flushBusy) return;
    final pendingN =
        await widget.localPrefs.countPendingSyncOpsForStore(widget.storeId);
    if (pendingN == 0 && !doPull) return;

    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;

    setState(() => _flushBusy = true);
    final cycle = await runSyncCycle(
      storeId: widget.storeId,
      prefs: widget.localPrefs,
      syncApi: widget.syncApi,
      deviceId: _terminal!.deviceId,
      appVersion: _terminal!.appVersion,
      doPull: doPull,
      doFlush: true,
    );
    if (!mounted) return;
    setState(() => _flushBusy = false);
    await _refreshPendingCount();
    if (!mounted) return;

    if (!silent && cycle.pullError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync pull: ${cycle.pullError}')),
      );
    }

    final r = cycle.flush;
    if (r.removedCount > 0) {
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              r.removedCount == 1
                  ? '1 operación de la cola sincronizada.'
                  : '${r.removedCount} operaciones de la cola sincronizadas.',
            ),
          ),
        );
      }
    } else if (!silent && r.apiMessage != null && pendingN > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.apiMessage!)),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<String> get _documentCurrencyOptions {
    final s = _settings;
    if (s == null) return const [];
    final f = s.functionalCurrency.code;
    final d = s.defaultSaleDocCurrency?.code;
    if (d == null || d.toUpperCase() == f.toUpperCase()) {
      return [f];
    }
    return [d, f];
  }

  String get _functionalCode => _settings?.functionalCurrency.code ?? '';

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

  Future<void> _reloadFxForDocumentCurrency() async {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    setState(() {
      _fxLoadError = null;
      _fxPair = null;
    });
    if (func.toUpperCase() == doc.toUpperCase()) {
      _rebuildCartDocumentPrices();
      if (mounted) setState(() {});
      return;
    }
    try {
      final pair = await _fetchFxPair(func, doc);
      if (!mounted) return;
      setState(() {
        _fxPair = pair;
        if (pair == null) {
          _fxLoadError =
              'No hay tasa $func → $doc. Registrá la tasa en Inicio o usá moneda documento = funcional.';
        }
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _fxPair = null;
        _fxLoadError = e.userMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fxPair = null;
        _fxLoadError = e.toString();
      });
    }
    _rebuildCartDocumentPrices();
    if (mounted) setState(() {});
  }

  void _rebuildCartDocumentPrices() {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    final next = <PosCartLine>[];
    for (final old in _cart) {
      final docPrice = PosSalePricing.documentUnitPrice(
        catalogPrice: old.catalogUnitPrice,
        catalogCurrency: old.catalogCurrency,
        documentCurrencyCode: doc,
        functionalCurrencyCode: func,
        pair: _fxPair,
      );
      if (docPrice == null) continue;
      next.add(
        PosCartLine(
          productId: old.productId,
          name: old.name,
          sku: old.sku,
          catalogUnitPrice: old.catalogUnitPrice,
          catalogCurrency: old.catalogCurrency,
          documentUnitPrice: docPrice,
          documentCurrencyCode: doc,
          quantity: old.quantity,
        ),
      );
    }
    if (next.length != _cart.length && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Algunas líneas se quitaron del ticket: moneda o tasa no compatibles.',
              ),
            ),
          );
        }
      });
    }
    _cart
      ..clear()
      ..addAll(next);
  }

  void _invalidateCheckoutIdempotency() {
    _pendingSaleId = null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.productsApi.listProducts(widget.storeId);
      if (!mounted) return;
      setState(() => _all = list);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _error = e.userMessage;
        _loading = false;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _error = e.toString();
        _loading = false;
      });
      return;
    }

    try {
      final settings = await widget.storesApi.getBusinessSettings(widget.storeId);
      if (!mounted) return;
      final doc = settings.defaultSaleDocCurrency?.code ??
          settings.functionalCurrency.code;
      setState(() {
        _settings = settings;
        _contextError = null;
        _selectedDocumentCurrency = doc;
      });
      await _reloadFxForDocumentCurrency();
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = null;
        _contextError = e.userMessage;
        _fxPair = null;
        _selectedDocumentCurrency = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _settings = null;
        _contextError = e.toString();
        _fxPair = null;
        _selectedDocumentCurrency = null;
      });
    }

    if (!mounted) return;
    setState(() => _loading = false);
    await _refreshPendingCount();
  }

  List<CatalogProduct> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  String? _documentPriceLabel(CatalogProduct p) {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return null;
    final unit = PosSalePricing.documentUnitPrice(
      catalogPrice: p.price,
      catalogCurrency: p.currency,
      documentCurrencyCode: doc,
      functionalCurrencyCode: s.functionalCurrency.code,
      pair: _fxPair,
    );
    if (unit == null) return null;
    return '$unit $doc';
  }

  void _addProductToCart(CatalogProduct p, {int qty = 1}) {
    _invalidateCheckoutIdempotency();
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _contextError ?? 'No se cargó la configuración de la tienda.',
          ),
        ),
      );
      return;
    }
    final func = s.functionalCurrency.code;
    if (func.toUpperCase() != doc.toUpperCase() && _fxPair == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fxLoadError ??
                'Falta tasa $func → $doc para vender en $doc.',
          ),
        ),
      );
      return;
    }
    final docPrice = PosSalePricing.documentUnitPrice(
      catalogPrice: p.price,
      catalogCurrency: p.currency,
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      pair: _fxPair,
    );
    if (docPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'El producto está en ${p.currency}: solo se admite precio en $doc '
            'o en $func con tasa cargada.',
          ),
        ),
      );
      return;
    }

    final i = _cart.indexWhere((l) => l.productId == p.id);
    setState(() {
      if (i >= 0) {
        _cart[i].quantity += qty;
      } else {
        _cart.add(
          PosCartLine(
            productId: p.id,
            name: p.name,
            sku: p.sku,
            catalogUnitPrice: p.price,
            catalogCurrency: p.currency,
            documentUnitPrice: docPrice,
            documentCurrencyCode: doc,
            quantity: qty,
          ),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${p.name} × $qty en el ticket')),
    );
  }

  Future<void> _openScanner() async {
    if (!BarcodeScannerScreen.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El escáner solo está disponible en Android e iOS.'),
        ),
      );
      return;
    }
    final code = await BarcodeScannerScreen.open(context);
    if (!mounted || code == null || code.isEmpty) return;

    final p = _findByBarcode(_all, code);
    if (p != null) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          var q = 1;
          final docLabel = _documentPriceLabel(p);
          return StatefulBuilder(
            builder: (ctx, setModal) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(p.name, style: Theme.of(ctx).textTheme.titleMedium),
                    Text('SKU ${p.sku} · ${p.price} ${p.currency}'),
                    if (docLabel != null)
                      Text(
                        'En ticket: $docLabel',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Text('Cantidad'),
                        const Spacer(),
                        IconButton(
                          onPressed: q > 1 ? () => setModal(() => q--) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$q'),
                        IconButton(
                          onPressed: () => setModal(() => q++),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _addProductToCart(p, qty: q);
                      },
                      child: const Text('Agregar al ticket'),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } else {
      setState(() => _search.text = code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ningún producto activo con código "$code". '
            'Buscá en Catálogo o cargá el código de barras en la ficha del producto.',
          ),
        ),
      );
    }
  }

  Future<void> _onDocumentCurrencyChanged(String? code) async {
    if (code == null || code == _selectedDocumentCurrency) return;
    setState(() => _selectedDocumentCurrency = code);
    await _reloadFxForDocumentCurrency();
    if (mounted) setState(() {});
  }

  Future<void> _onCheckout() async {
    if (_cart.isEmpty) return;
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración de tienda no disponible.')),
      );
      return;
    }
    final func = s.functionalCurrency.code;
    if (func.toUpperCase() != doc.toUpperCase() && _fxPair == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fxLoadError ?? 'Definí la tasa del día antes de cobrar.',
          ),
        ),
      );
      return;
    }

    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;

    _pendingSaleId ??= ClientMutationId.newId();
    setState(() => _checkoutBusy = true);
    final restBody = SaleCheckoutPayload.build(
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      lines: List<PosCartLine>.from(_cart),
      fxPair: _fxPair,
      deviceId: _terminal!.deviceId,
      appVersion: _terminal!.appVersion,
      clientSaleId: _pendingSaleId,
    );
    try {
      await widget.salesApi.createSale(widget.storeId, restBody);
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _pendingSaleId = null;
        _checkoutBusy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Venta registrada.')),
      );
      unawaited(_runSyncCycle(silent: true, doPull: false));
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _checkoutBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      if (isLikelyNetworkFailure(e)) {
        final syncOpId = ClientMutationId.newId();
        final saleMap = SaleCheckoutPayload.syncSaleFromRestBody(
          restBody,
          widget.storeId,
          fxSource: 'POS_OFFLINE',
        );
        await widget.localPrefs.appendPendingSale(
          PendingSaleEntry(
            opId: syncOpId,
            storeId: widget.storeId,
            sale: saleMap,
            opTimestampIso: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        if (!mounted) return;
        setState(() {
          _cart.clear();
          _pendingSaleId = null;
          _checkoutBusy = false;
        });
        await _refreshPendingCount();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión: venta guardada en cola. Se enviará con sync/push '
              'cuando haya red (botón Sincronizar o al abrir Venta).',
            ),
          ),
        );
        return;
      }
      setState(() => _checkoutBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  String _fxReferenceLine() {
    final doc = _selectedDocumentCurrency;
    final func = _functionalCode;
    if (doc == null || func.isEmpty) return '';
    if (func.toUpperCase() == doc.toUpperCase()) {
      return 'Moneda documento = funcional ($func). Sin conversión.';
    }
    final rate = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: func,
      documentCode: doc,
      pair: _fxPair,
    );
    final date = _fxPair?.rate.effectiveDate ?? '';
    final d = date.length >= 10 ? date.substring(0, 10) : date;
    return 'Ref.: 1 $func = $rate $doc${d.isNotEmpty ? ' · $d' : ''}';
  }

  int get _cartUnits =>
      _cart.fold<int>(0, (sum, l) => sum + l.quantity);

  String? get _cartTotalDocument {
    if (_cart.isEmpty || _selectedDocumentCurrency == null) return null;
    return MoneyStringMath.sum(_cart.map((l) => l.lineTotalDocument));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Venta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear código',
            onPressed: _loading ? null : _openScanner,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_contextError != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Tienda: $_contextError',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          if (_pendingSyncCount > 0)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_upload_outlined,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$_pendingSyncCount operación(es) en cola (ventas o ajustes; sync/push).',
                        style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                    if (_flushBusy)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: Padding(
                          padding: EdgeInsets.all(4),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: () =>
                            _runSyncCycle(silent: false, doPull: true),
                        child: const Text('Sincronizar'),
                      ),
                  ],
                ),
              ),
            ),
          if (_settings != null && _selectedDocumentCurrency != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Ticket',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(width: 12),
                      if (_documentCurrencyOptions.length > 1)
                        DropdownButton<String>(
                          value: () {
                            final sel = _selectedDocumentCurrency!;
                            for (final c in _documentCurrencyOptions) {
                              if (c.toUpperCase() == sel.toUpperCase()) {
                                return c;
                              }
                            }
                            return _documentCurrencyOptions.first;
                          }(),
                          items: _documentCurrencyOptions
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ),
                              )
                              .toList(),
                          onChanged: _onDocumentCurrencyChanged,
                        )
                      else
                        Text(
                          _selectedDocumentCurrency!,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                    ],
                  ),
                  Text(
                    _fxReferenceLine(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  if (_fxLoadError != null &&
                      _functionalCode.toUpperCase() !=
                          _selectedDocumentCurrency!.toUpperCase())
                    Text(
                      _fxLoadError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, SKU o código de barras',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autocorrect: false,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: _load,
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height:
                                        MediaQuery.of(context).size.height * 0.2,
                                  ),
                                  Text(
                                    _all.isEmpty
                                        ? 'No hay productos activos. Cargalos en Inventario → Catálogo.'
                                        : 'Sin resultados.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                itemCount: _filtered.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final p = _filtered[i];
                                  final docLbl = _documentPriceLabel(p);
                                  return ListTile(
                                    title: Text(p.name),
                                    subtitle: Text(
                                      'SKU ${p.sku}'
                                      '${p.barcode != null && p.barcode!.isNotEmpty ? ' · ${p.barcode}' : ''}'
                                      '${docLbl != null ? '\nTicket: $docLbl' : ''}',
                                    ),
                                    isThreeLine: docLbl != null,
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (docLbl != null)
                                          Text(
                                            docLbl,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                        Text(
                                          '${p.price} ${p.currency}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                    onTap: () => _addProductToCart(p, qty: 1),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : Material(
              elevation: 8,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_cart.length} líneas · $_cartUnits u.',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (_cartTotalDocument != null &&
                                _selectedDocumentCurrency != null)
                              Text(
                                'Total ${_cartTotalDocument!} ${_selectedDocumentCurrency!}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _checkoutBusy
                            ? null
                            : () {
                                showModalBottomSheet<void>(
                                  context: context,
                                  showDragHandle: true,
                                  builder: (ctx) => ListView(
                                    padding: const EdgeInsets.all(16),
                                    children: [
                                      Text(
                                        'Ticket',
                                        style:
                                            Theme.of(ctx).textTheme.titleMedium,
                                      ),
                                      Text(
                                        _fxReferenceLine(),
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 8),
                                      ..._cart.map(
                                        (l) => ListTile(
                                          title: Text(l.name),
                                          subtitle: Text(
                                            '${l.documentUnitPrice} ${l.documentCurrencyCode} × ${l.quantity} '
                                            '= ${l.lineTotalDocument} ${l.documentCurrencyCode}\n'
                                            'Cat.: ${l.catalogUnitPrice} ${l.catalogCurrency}',
                                          ),
                                          isThreeLine: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                        child: const Text('Ver ticket'),
                      ),
                      FilledButton(
                        onPressed: _checkoutBusy ? null : _onCheckout,
                        child: _checkoutBusy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Cobrar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
