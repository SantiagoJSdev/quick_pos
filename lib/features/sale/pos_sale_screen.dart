import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/network/network_errors.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/recent_sale_ticket.dart';
import '../../core/models/pos_cart_line.dart';
import '../../core/pos/money_string_math.dart';
import '../../core/pos/pos_sale_pricing.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_sale_entry.dart';
import '../../core/sync/sync_cycle.dart';
import 'barcode_scanner_screen.dart';
import 'pos_cart_quantity.dart';
import 'pos_sale_sheets.dart';
import 'pos_sale_ui_tokens.dart';
import 'pos_sale_widgets.dart';

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
    required this.catalogInvalidationBus,
    required this.localPrefs,
    this.onRequestExit,
  });

  final String storeId;
  final ProductsApi productsApi;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final SalesApi salesApi;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final LocalPrefs localPrefs;

  /// Si no es null (p. ej. módulo Ventas), muestra atrás en la barra superior.
  final VoidCallback? onRequestExit;

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
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
    _searchFocus.addListener(() => setState(() {}));
    _load();
    PosTerminalInfo.load(widget.localPrefs).then((t) {
      if (mounted) setState(() => _terminal = t);
    });
    widget.catalogInvalidationBus.addListener(_onCatalogInvalidated);
    _refreshPendingCount();
  }

  void _onCatalogInvalidated() {
    if (!mounted) return;
    unawaited(_load());
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
      catalogInvalidation: widget.catalogInvalidationBus,
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
    widget.catalogInvalidationBus.removeListener(_onCatalogInvalidated);
    _search.dispose();
    _searchFocus.dispose();
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
        _fxLoadError = e.userMessageForSupport;
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
      final list = await widget.productsApi.listProducts(
        widget.storeId,
        includeInactive: false,
      );
      if (!mounted) return;
      setState(() => _all = list);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _error = e.userMessageForSupport;
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
        _contextError = e.userMessageForSupport;
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

  void _addProductToCart(CatalogProduct p, {String addQty = '1'}) {
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

    final add = PosCartQuantity.normalize(addQty);
    final i = _cart.indexWhere((l) => l.productId == p.id);
    setState(() {
      if (i >= 0) {
        _cart[i].quantity = PosCartQuantity.add(_cart[i].quantity, add);
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
            quantity: add,
          ),
        );
      }
    });
    _search.clear();
    _searchFocus.unfocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${p.name} × $add en el ticket')),
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
                        _addProductToCart(p, addQty: '$q');
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
      final res = await widget.salesApi.createSale(widget.storeId, restBody);
      if (!mounted) return;
      final totalDoc = _cartTotalDocument;
      var sid = res['id']?.toString().trim();
      if (sid == null || sid.isEmpty) {
        sid = _pendingSaleId ?? '';
      }
      if (sid.isNotEmpty && totalDoc != null) {
        await widget.localPrefs.prependRecentSaleTicket(
          RecentSaleTicket(
            storeId: widget.storeId,
            saleId: sid,
            totalDocument: totalDoc,
            documentCurrencyCode: doc,
            recordedAtIso: DateTime.now().toUtc().toIso8601String(),
            status: RecentSaleTicket.statusSynced,
          ),
        );
        if (!mounted) return;
      }
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
        SnackBar(content: Text(e.userMessageForSupport)),
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
        final totalDoc = _cartTotalDocument;
        final clientSid = _pendingSaleId;
        if (clientSid != null &&
            clientSid.isNotEmpty &&
            totalDoc != null) {
          await widget.localPrefs.prependRecentSaleTicket(
            RecentSaleTicket(
              storeId: widget.storeId,
              saleId: clientSid,
              totalDocument: totalDoc,
              documentCurrencyCode: doc,
              recordedAtIso: DateTime.now().toUtc().toIso8601String(),
              status: RecentSaleTicket.statusQueued,
            ),
          );
          if (!mounted) return;
        }
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

  String _cartQtySummary() {
    var t = 0.0;
    for (final l in _cart) {
      t += PosCartQuantity.parse(l.quantity);
    }
    if (t == t.roundToDouble()) return '${t.round()}';
    return PosCartQuantity.stringify(t);
  }

  String? get _cartTotalDocument {
    if (_cart.isEmpty || _selectedDocumentCurrency == null) return null;
    return MoneyStringMath.sum(_cart.map((l) => l.lineTotalDocument));
  }

  String? get _cartTotalFunctional {
    final td = _cartTotalDocument;
    if (td == null) return null;
    return _functionalFromDocument(td);
  }

  String _functionalFromDocument(String documentAmount) {
    final func = _functionalCode;
    final doc = _selectedDocumentCurrency ?? '';
    if (func.isEmpty || doc.isEmpty) return documentAmount;
    if (func.toUpperCase() == doc.toUpperCase()) return documentAmount;
    final r = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: func,
      documentCode: doc,
      pair: _fxPair,
    );
    return MoneyStringMath.divide(documentAmount, r, fractionDigits: 2);
  }

  String _rateBadgeHeadline() {
    final doc = _selectedDocumentCurrency;
    final func = _functionalCode;
    if (doc == null || func.isEmpty) return 'Sin tasa';
    if (func.toUpperCase() == doc.toUpperCase()) {
      return '$func (sin conversión)';
    }
    if (_fxPair == null) return 'Sin tasa $func → $doc';
    final r = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: func,
      documentCode: doc,
      pair: _fxPair,
    );
    return '1 $func = $r $doc';
  }

  String _rateBadgeSub() {
    final r = _fxPair?.rate;
    if (r == null) {
      if (_functionalCode.isNotEmpty &&
          _selectedDocumentCurrency != null &&
          _functionalCode.toUpperCase() ==
              _selectedDocumentCurrency!.toUpperCase()) {
        return 'Misma moneda funcional y documento';
      }
      return 'Definí la tasa en Inicio';
    }
    final c = r.convention?.trim();
    if (c != null && c.isNotEmpty) return c;
    final s = r.source?.trim();
    if (s != null && s.isNotEmpty) return s;
    final d = r.effectiveDate.trim();
    if (d.length >= 10) return d.substring(0, 10);
    return 'Tasa tienda';
  }

  String _posCurrencyLabel(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
        return '🇺🇸 $code';
      case 'VES':
        return '🇻🇪 $code';
      default:
        return code;
    }
  }

  List<CatalogProduct> get _searchPreview {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final found = _all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList();
    found.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return found.take(6).toList();
  }

  void _bumpLine(int index, double delta) {
    _invalidateCheckoutIdempotency();
    final cur = PosCartQuantity.parse(_cart[index].quantity);
    final next = cur + delta;
    if (next <= 0) {
      setState(() => _cart.removeAt(index));
      return;
    }
    setState(() {
      _cart[index].quantity = PosCartQuantity.stringify(next);
    });
  }

  Future<void> _onLineQtyTap(int index) async {
    final line = _cart[index];
    final res = await showPosQuantityNumpadSheet(
      context,
      productName: line.name,
      initialQuantity: line.quantity,
    );
    if (!mounted || res == null) return;
    final n = PosCartQuantity.normalize(res);
    setState(() {
      _invalidateCheckoutIdempotency();
      _cart[index].quantity = n;
    });
  }

  void _removeLineByProductId(String productId) {
    setState(() {
      _invalidateCheckoutIdempotency();
      _cart.removeWhere((l) => l.productId == productId);
    });
  }

  void _clearCart() {
    if (_cart.isEmpty) return;
    setState(() {
      _invalidateCheckoutIdempotency();
      _cart.clear();
    });
  }

  void _openScanChoices() {
    showPosScanSheet(
      context,
      onOpenCamera: _openScanner,
      onSimulate: _simulateRandomScan,
    );
  }

  void _simulateRandomScan() {
    final active = _all.where((p) => p.active).toList();
    if (active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay productos en catálogo.')),
      );
      return;
    }
    final p = active[Random().nextInt(active.length)];
    _addProductToCart(p, addQty: '1');
  }

  @override
  Widget build(BuildContext context) {
    final doc = _selectedDocumentCurrency;
    final func = _functionalCode;
    final td = _cartTotalDocument ?? '0.00';
    final tf = _cartTotalFunctional ?? '0.00';
    final cartEmpty = _cart.isEmpty;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: PosSaleUi.bg,
        brightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: PosSaleUi.bg,
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            if (_contextError != null)
              Material(
                color: PosSaleUi.error.withValues(alpha: 0.2),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Tienda: $_contextError',
                    style: const TextStyle(color: PosSaleUi.text),
                  ),
                ),
              ),
            if (_pendingSyncCount > 0)
              Material(
                color: PosSaleUi.primaryDim,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_upload_outlined,
                          color: PosSaleUi.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '$_pendingSyncCount en cola (sync/push).',
                          style: const TextStyle(
                            color: PosSaleUi.text,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_flushBusy)
                        const SizedBox(
                          width: 28,
                          height: 28,
                          child: Padding(
                            padding: EdgeInsets.all(4),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: PosSaleUi.primary,
                            ),
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
            PosSaleTopBar(
              rateHeadline: _rateBadgeHeadline(),
              rateSub: _rateBadgeSub(),
              onRefresh: _load,
              onSync: () => _runSyncCycle(silent: false, doPull: true),
              syncBusy: _flushBusy,
              showSyncDot: _pendingSyncCount > 0,
              onBack: widget.onRequestExit,
            ),
            PosSaleSearchBlock(
              controller: _search,
              focusNode: _searchFocus,
              onScanTap: _openScanChoices,
              onClear: () {
                _search.clear();
                setState(() {});
              },
            ),
            if (_fxLoadError != null &&
                doc != null &&
                func.isNotEmpty &&
                func.toUpperCase() != doc.toUpperCase())
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  _fxLoadError!,
                  style: const TextStyle(color: PosSaleUi.error, fontSize: 12),
                ),
              ),
            if (_search.text.trim().isNotEmpty && !_loading && _error == null)
              Material(
                color: PosSaleUi.surface2,
                elevation: 3,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: _searchPreview.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Sin coincidencias',
                            style: TextStyle(color: PosSaleUi.textMuted),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _searchPreview.length,
                          separatorBuilder: (context, i) => const Divider(
                            height: 1,
                            color: PosSaleUi.divider,
                          ),
                          itemBuilder: (context, i) {
                            final p = _searchPreview[i];
                            final docLbl = _documentPriceLabel(p);
                            final bc = p.barcode?.trim();
                            return PosSaleSearchResultTile(
                              product: p,
                              primaryLine:
                                  docLbl ?? '${p.price} ${p.currency}',
                              secondaryLine: [
                                'SKU ${p.sku}',
                                if (bc != null && bc.isNotEmpty) bc,
                              ].join(' · '),
                              onTap: () => _addProductToCart(p),
                            );
                          },
                        ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: PosSaleUi.primary,
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: PosSaleUi.text),
                                ),
                                const SizedBox(height: 16),
                                FilledButton(
                                  onPressed: _load,
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                              child: Row(
                                children: [
                                  Text(
                                    'TICKET ACTUAL',
                                    style: PosSaleUi.titleCart(context),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: PosSaleUi.primary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _cartQtySummary(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: cartEmpty
                                  ? Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(32),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.shopping_cart_outlined,
                                              size: 56,
                                              color: PosSaleUi.textFaint,
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'El ticket está vacío',
                                              style: TextStyle(
                                                color: PosSaleUi.textMuted,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Buscá un producto o escaneá el código.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: PosSaleUi.textFaint,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  : RefreshIndicator(
                                      color: PosSaleUi.primary,
                                      onRefresh: _load,
                                      child: ListView.separated(
                                        itemCount: _cart.length,
                                        separatorBuilder: (context, i) =>
                                            const Divider(
                                          height: 1,
                                          color: PosSaleUi.divider,
                                        ),
                                        itemBuilder: (context, i) {
                                          final l = _cart[i];
                                          final uf = _functionalFromDocument(
                                            l.documentUnitPrice,
                                          );
                                          final lf = _functionalFromDocument(
                                            l.lineTotalDocument,
                                          );
                                          return PosSaleCartLineTile(
                                            line: l,
                                            unitFunctional: uf,
                                            lineTotalFunctional: lf,
                                            functionalCode: func,
                                            documentCode:
                                                doc ?? l.documentCurrencyCode,
                                            onMinus: () => _bumpLine(i, -1),
                                            onPlus: () => _bumpLine(i, 1),
                                            onQtyTap: () => _onLineQtyTap(i),
                                            onDismissed: () =>
                                                _removeLineByProductId(
                                                    l.productId),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),
            ),
            if (!_loading && _error == null && doc != null)
              PosSaleCheckoutPanel(
                functionalCode: func,
                documentCode: doc,
                functionalTotalLabel: _posCurrencyLabel(func),
                documentTotalLabel: _posCurrencyLabel(doc),
                totalFunctional: tf,
                totalDocument: td,
                subtotalLabel: '$td $doc',
                itemsSummary:
                    '${_cart.length} líneas · ${_cartQtySummary()} u.',
                cartNotEmpty: !cartEmpty,
                chargeInlineHint: cartEmpty ? '' : '$tf $func',
                onClear: _clearCart,
                onCharge: _onCheckout,
                chargeBusy: _checkoutBusy,
                onDiscount: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Descuentos: próximamente.'),
                    ),
                  );
                },
                currencySelector: _documentCurrencyOptions.length > 1
                    ? Row(
                        children: [
                          const Text(
                            'Moneda del ticket',
                            style: TextStyle(
                              color: PosSaleUi.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
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
                            dropdownColor: PosSaleUi.surface3,
                            underline: const SizedBox.shrink(),
                            style: const TextStyle(
                              color: PosSaleUi.text,
                              fontSize: 13,
                            ),
                            items: _documentCurrencyOptions
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(c),
                                  ),
                                )
                                .toList(),
                            onChanged: _onDocumentCurrencyChanged,
                          ),
                        ],
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
