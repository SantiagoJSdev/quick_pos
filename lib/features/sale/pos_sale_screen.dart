import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/network/network_errors.dart';
import '../../core/network/product_image_url.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/held_ticket.dart';
import '../../core/models/recent_sale_ticket.dart';
import '../../core/models/pos_cart_line.dart';
import '../../core/pos/money_string_math.dart';
import '../../core/pos/pos_sale_pricing.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_sale_entry.dart';
import '../../core/sync/sync_cycle.dart';
import '../shell/shell_online_scope.dart';
import 'barcode_scanner_screen.dart';
import 'pos_cart_quantity.dart';
import 'pos_held_tickets_ui.dart';
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
  static const double _kSearchRowExtent = 72;
  static const int _kSearchVisibleRows = 5;

  /// Si el servidor no responde a tiempo, dejamos de mostrar el spinner y usamos caché (como offline).
  static const Duration _kPosOnlineLoadBudget = Duration(seconds: 8);

  /// Min vertical space kept for ticket + list; search suggestions use the rest (up to 5 rows).
  static const double _kSearchCartReserveMin = 96;
  static const double _kSearchCartReserveMax = 168;
  static const double _kSearchCartReserveFraction = 0.26;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _paymentFunctionalCtrl = TextEditingController();
  double _appliedFunctionalPayment = 0;
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
  Timer? _pendingCountPoll;

  String? _cartFeedback;
  bool _cartFeedbackIsError = false;
  Timer? _cartFeedbackTimer;

  int _heldTicketsCount = 0;
  String? _activeHeldTicketId;
  bool _shellOnline = true;
  bool _shellManualForceOffline = false;
  bool _shellBackendReachable = true;

  /// Borde inferior del bloque buscador (+ aviso FX): el overlay de sugerencias empieza debajo.
  final GlobalKey _posSearchAnchorKey = GlobalKey(debugLabel: 'pos_search_anchor');

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _searchFocus.addListener(() => setState(() {}));
    PosTerminalInfo.load(widget.localPrefs).then((t) {
      if (!mounted) return;
      setState(() => _terminal = t);
      unawaited(_refreshHeldCount());
    });
    widget.catalogInvalidationBus.addListener(_onCatalogInvalidated);
    _refreshPendingCount();
    _pendingCountPoll = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshPendingCount(),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<ShellOnlineScope>();
    final nextOnline = scope?.isOnline ?? true;
    final nextManual = scope?.manualForceOffline ?? false;
    final nextBackend = scope?.backendReachable ?? true;
    if (_shellOnline == nextOnline &&
        _shellManualForceOffline == nextManual &&
        _shellBackendReachable == nextBackend) {
      return;
    }
    _shellOnline = nextOnline;
    _shellManualForceOffline = nextManual;
    _shellBackendReachable = nextBackend;
    unawaited(_load());
  }

  void _onCatalogInvalidated() {
    if (!mounted) return;
    unawaited(_load());
  }

  Future<void> _refreshPendingCount() async {
    final n = await widget.localPrefs.countPendingSyncOpsForStore(
      widget.storeId,
    );
    if (mounted) setState(() => _pendingSyncCount = n);
  }

  /// [doPull]: actualiza watermark con `GET /sync/pull`; [doFlush]: envía cola mixta.
  Future<void> _runSyncCycle({bool silent = false, bool doPull = true}) async {
    if (!_shellOnline) {
      if (!silent && mounted) {
        _showCheckoutPanelMessage(
          'Modo offline: la sincronización se hará al volver online.',
          error: false,
          duration: const Duration(seconds: 2),
        );
      }
      return;
    }
    if (_flushBusy) return;
    final pendingN = await widget.localPrefs.countPendingSyncOpsForStore(
      widget.storeId,
    );
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
      _showCheckoutPanelMessage('Sync pull: ${cycle.pullError}', error: true);
    }

    final r = cycle.flush;
    if (r.removedCount > 0) {
      final msg = r.removedCount == 1
          ? '1 operación de la cola sincronizada.'
          : '${r.removedCount} operaciones de la cola sincronizadas.';
      if (!silent) {
        _showCheckoutPanelMessage(msg);
      }
    } else if (!silent && r.apiMessage != null && pendingN > 0) {
      final suffix = r.hadManualReviewFailure
          ? '\nRequiere revisión manual (error de validación/negocio).'
          : (r.hadRetryableFailure ? '\nSe reintentará automáticamente.' : '');
      _showCheckoutPanelMessage('${r.apiMessage!}$suffix', error: true);
    }
  }

  bool get _checkoutPanelVisible =>
      !_loading && _error == null && _selectedDocumentCurrency != null;

  /// Servidor alcanzable pero la app sigue en offline (p. ej. «Poner offline» en Inicio).
  bool get _pendingQueueServerAvailableHint =>
      !_shellOnline &&
      _shellManualForceOffline &&
      _shellBackendReachable &&
      _pendingSyncCount > 0;

  void _logPosCheckoutApiFailure(ApiError e, String uiMessage) {
    final summary = _cart
        .map((l) => '${l.productId} x${l.quantity} (${l.name})')
        .join('; ');
    debugPrint(
      '[POS checkout] storeId=${widget.storeId} http=${e.statusCode} '
      'error=${e.error} messages=${e.messages} requestId=${e.requestId} '
      'uiMessage=${uiMessage.replaceAll('\n', ' ')} cart=[$summary]',
    );
  }

  void _showCheckoutPanelMessage(
    String message, {
    bool error = false,
    Duration? duration,
  }) {
    _cartFeedbackTimer?.cancel();
    _pendingCountPoll?.cancel();
    final d = duration ?? Duration(seconds: error ? 4 : 3);
    if (_checkoutPanelVisible) {
      setState(() {
        _cartFeedback = message;
        _cartFeedbackIsError = error;
      });
      _cartFeedbackTimer = Timer(d, () {
        if (!mounted) return;
        setState(() {
          _cartFeedback = null;
          _cartFeedbackIsError = false;
        });
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showCartFeedback(String message) {
    _showCheckoutPanelMessage(
      message,
      error: false,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  void dispose() {
    _cartFeedbackTimer?.cancel();
    widget.catalogInvalidationBus.removeListener(_onCatalogInvalidated);
    _search.dispose();
    _searchFocus.dispose();
    _paymentFunctionalCtrl.dispose();
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

  Future<void> _reloadFxForDocumentCurrency({
    bool rebuildDocumentLinePrices = true,
  }) async {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    setState(() {
      _fxLoadError = null;
      _fxPair = null;
    });
    if (func.toUpperCase() == doc.toUpperCase()) {
      if (rebuildDocumentLinePrices) {
        _rebuildCartDocumentPrices();
      }
      if (mounted) setState(() {});
      return;
    }
    if (!_shellOnline) {
      await _applyFxFromPrefsCacheOnly();
      if (rebuildDocumentLinePrices) {
        _rebuildCartDocumentPrices();
      }
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
      if (pair != null) {
        await widget.localPrefs.savePosFxPairCache(
          storeId: widget.storeId,
          functionalCode: func,
          documentCode: doc,
          pair: pair,
        );
      }
    } on ApiError catch (e) {
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
          _fxLoadError = e.userMessageForSupport;
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
    if (rebuildDocumentLinePrices) {
      _rebuildCartDocumentPrices();
    }
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
          isByWeight: old.isByWeight,
          displayGrams: old.displayGrams,
          pricePerKgFunctional: old.pricePerKgFunctional,
          lineAmountFunctional: old.lineAmountFunctional,
          lineAmountDocument: old.lineAmountDocument,
        ),
      );
    }
    if (next.length != _cart.length && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showCheckoutPanelMessage(
            'Algunas líneas se quitaron del ticket: moneda o tasa no compatibles.',
            error: true,
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

  Future<void> _refreshHeldCount() async {
    try {
      _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
      if (!mounted) return;
      final n = await widget.localPrefs.countHeldTicketsForStoreAndDevice(
        storeId: widget.storeId,
        deviceId: _terminal!.deviceId,
      );
      if (mounted) setState(() => _heldTicketsCount = n);
    } catch (_) {
      if (mounted) setState(() => _heldTicketsCount = 0);
    }
  }

  String? _matchDocumentCurrencyOption(String code) {
    final c = code.trim().toUpperCase();
    for (final o in _documentCurrencyOptions) {
      if (o.toUpperCase() == c) return o;
    }
    return null;
  }

  Future<void> _persistCurrentCartAsHold(String? alias, String? note) async {
    if (_cart.isEmpty) return;
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;
    final func = s.functionalCurrency.code;
    final rest = SaleCheckoutPayload.build(
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      lines: List<PosCartLine>.from(_cart),
      fxPair: _fxPair,
      deviceId: _terminal!.deviceId,
      appVersion: _terminal!.appVersion,
      fxSource: 'POS_PREVIEW',
    );
    final fxRaw = rest['fxSnapshot'];
    final fxMap = fxRaw is Map
        ? Map<String, dynamic>.from(fxRaw)
        : <String, dynamic>{};
    final id = ClientMutationId.newId();
    final tf = _cartTotalFunctional;
    final ticket = HeldTicket.fromPosCart(
      id: id,
      storeId: widget.storeId,
      deviceId: _terminal!.deviceId,
      documentCurrencyCode: doc,
      fxSnapshot: fxMap,
      cartLines: List<PosCartLine>.from(_cart),
      alias: alias,
      note: note,
      totalFunctional: tf,
    );
    final oldHeld = _activeHeldTicketId;
    if (oldHeld != null) {
      await widget.localPrefs.deleteHeldTicket(oldHeld);
    }
    await widget.localPrefs.upsertHeldTicket(ticket);
    if (!mounted) return;
    setState(() {
      _cart.clear();
      _activeHeldTicketId = null;
      _invalidateCheckoutIdempotency();
    });
    _clearMixedPaymentInputs();
    await _refreshHeldCount();
    if (mounted) _showCartFeedback('Ticket guardado en espera');
  }

  Future<void> _putCartOnHold() async {
    if (_cart.isEmpty) return;
    if (_settings == null || _selectedDocumentCurrency == null) {
      _showCheckoutPanelMessage(
        'Configuración de tienda no disponible.',
        error: true,
      );
      return;
    }
    await showPosSaveHeldTicketSheet(
      context,
      onConfirm: _persistCurrentCartAsHold,
    );
  }

  Future<void> _applyHeldTicketToCart(HeldTicket t) async {
    final docCode = _matchDocumentCurrencyOption(t.documentCurrencyCode);
    if (docCode == null) {
      if (!mounted) return;
      _showCheckoutPanelMessage(
        'La moneda del ticket guardado (${t.documentCurrencyCode}) '
        'no está disponible para esta tienda.',
        error: true,
      );
      return;
    }
    setState(() {
      _selectedDocumentCurrency = docCode;
      _cart
        ..clear()
        ..addAll(t.lines.map((l) => l.toPosCartLine()));
      _activeHeldTicketId = t.id;
      _invalidateCheckoutIdempotency();
    });
    _clearMixedPaymentInputs();
    await _reloadFxForDocumentCurrency(rebuildDocumentLinePrices: false);
    if (mounted) _showCartFeedback('Ticket recuperado desde guardados');
  }

  Future<void> _recoverHeldTicket(HeldTicket t) async {
    if (_cart.isNotEmpty) {
      final choice = await showRecoverCartConflictDialog(context);
      if (!mounted) return;
      if (choice == null || choice == RecoverCartConflictChoice.cancel) {
        return;
      }
      if (choice == RecoverCartConflictChoice.saveCurrentAndOpen) {
        await showPosSaveHeldTicketSheet(
          context,
          onConfirm: _persistCurrentCartAsHold,
        );
        if (!mounted) return;
      } else {
        setState(() {
          _cart.clear();
          _activeHeldTicketId = null;
          _invalidateCheckoutIdempotency();
        });
      }
    }
    await _applyHeldTicketToCart(t);
  }

  Future<void> _openHeldTicketsList() async {
    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;
    final list = await widget.localPrefs.listHeldTicketsForStoreAndDevice(
      storeId: widget.storeId,
      deviceId: _terminal!.deviceId,
    );
    if (!mounted) return;
    await showPosHeldTicketsListSheet(
      context,
      tickets: list,
      reloadTickets: () async {
        _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
        return widget.localPrefs.listHeldTicketsForStoreAndDevice(
          storeId: widget.storeId,
          deviceId: _terminal!.deviceId,
        );
      },
      onRecover: (t) {
        unawaited(_recoverHeldTicket(t));
      },
      onRename: (t) async {
        final alias = await showRenameHeldTicketDialog(
          context,
          currentAlias: t.alias ?? '',
        );
        if (!mounted || alias == null) return;
        final a = alias.trim();
        await widget.localPrefs.updateHeldTicketAlias(
          id: t.id,
          alias: a.isEmpty ? null : a,
        );
        await _refreshHeldCount();
        if (mounted) setState(() {});
      },
      onDelete: (t) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Eliminar ticket en espera'),
            content: Text(
              '¿Eliminar «${t.displayTitle}»? No se puede deshacer.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        await widget.localPrefs.deleteHeldTicket(t.id);
        if (_activeHeldTicketId == t.id) {
          setState(() => _activeHeldTicketId = null);
        }
        await _refreshHeldCount();
        if (mounted) setState(() {});
      },
    );
    await _refreshHeldCount();
  }

  Future<void> _bootstrapShellOfflineLoad() async {
    final cachedCatalog = await widget.localPrefs.loadCatalogProductsCache();
    final active = cachedCatalog.where((p) => p.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final cached = await widget.localPrefs.loadBusinessSettingsCache(
      widget.storeId,
    );
    if (!mounted) return;
    if (cached != null) {
      final doc =
          cached.defaultSaleDocCurrency?.code ?? cached.functionalCurrency.code;
      setState(() {
        _all = active;
        _settings = cached;
        _contextError = null;
        _selectedDocumentCurrency = doc;
        _error = active.isEmpty
            ? 'Sin productos en caché. Conectate para sincronizar el catálogo.'
            : null;
      });
      await _applyFxFromPrefsCacheOnly();
    } else {
      setState(() {
        _all = active;
        _settings = null;
        _contextError =
            'Sin configuración en caché. Conectate para cargar la tienda.';
        _selectedDocumentCurrency = null;
        _fxPair = null;
        _fxLoadError = null;
        _error = active.isEmpty
            ? 'Sin datos en caché. Conectate para sincronizar.'
            : null;
      });
    }
  }

  Future<void> _applyFxFromPrefsCacheOnly() async {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    if (func.toUpperCase() == doc.toUpperCase()) {
      setState(() {
        _fxLoadError = null;
        _fxPair = null;
      });
      _rebuildCartDocumentPrices();
      return;
    }
    final cached = await widget.localPrefs.loadPosFxPairCache(
      storeId: widget.storeId,
      functionalCode: func,
      documentCode: doc,
    );
    if (!mounted) return;
    setState(() {
      _fxPair = cached;
      _fxLoadError = cached == null
          ? 'Sin tasa en caché. Conectate o cargá la tasa en Inicio.'
          : null;
    });
    _rebuildCartDocumentPrices();
  }

  /// `true` → [_load] debe hacer `loading=false` y refrescos; `false` → ya se cerró el loading (p. ej. catálogo vacío).
  Future<bool> _loadFromNetworkWithCacheFallback() async {
    try {
      final list = await widget.productsApi.listProducts(
        widget.storeId,
        includeInactive: false,
      );
      await widget.localPrefs.saveCatalogProductsCache(list);
      if (!mounted) return false;
      setState(() => _all = list);
    } on ApiError catch (e) {
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      if (!mounted) return false;
      if (cached.isEmpty) {
        setState(() {
          _all = [];
          _error = e.userMessageForSupport;
          _loading = false;
        });
        return false;
      }
      setState(() => _all = cached);
    } catch (e) {
      final cached = await widget.localPrefs.loadCatalogProductsCache();
      if (!mounted) return false;
      if (cached.isEmpty) {
        setState(() {
          _all = [];
          _error = e.toString();
          _loading = false;
        });
        return false;
      }
      setState(() => _all = cached);
    }

    try {
      final settings = await widget.storesApi.getBusinessSettings(
        widget.storeId,
      );
      await widget.localPrefs.saveBusinessSettingsCache(
        widget.storeId,
        _businessSettingsToCacheMap(settings),
      );
      if (!mounted) return false;
      final doc =
          settings.defaultSaleDocCurrency?.code ??
          settings.functionalCurrency.code;
      setState(() {
        _settings = settings;
        _contextError = null;
        _selectedDocumentCurrency = doc;
      });
      await _reloadFxForDocumentCurrency();
    } on ApiError catch (e) {
      final cached = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      if (!mounted) return false;
      if (cached != null) {
        final doc =
            cached.defaultSaleDocCurrency?.code ??
            cached.functionalCurrency.code;
        setState(() {
          _settings = cached;
          _contextError = null;
          _selectedDocumentCurrency = doc;
        });
        await _reloadFxForDocumentCurrency();
      } else {
        setState(() {
          _settings = null;
          _contextError = e.userMessageForSupport;
          _fxPair = null;
          _selectedDocumentCurrency = null;
        });
      }
    } catch (e) {
      final cached = await widget.localPrefs.loadBusinessSettingsCache(
        widget.storeId,
      );
      if (!mounted) return false;
      if (cached != null) {
        final doc =
            cached.defaultSaleDocCurrency?.code ??
            cached.functionalCurrency.code;
        setState(() {
          _settings = cached;
          _contextError = null;
          _selectedDocumentCurrency = doc;
        });
        await _reloadFxForDocumentCurrency();
      } else {
        setState(() {
          _settings = null;
          _contextError = e.toString();
          _fxPair = null;
          _selectedDocumentCurrency = null;
        });
      }
    }

    return true;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (!_shellOnline) {
      await _bootstrapShellOfflineLoad();
      if (!mounted) return;
      setState(() => _loading = false);
      await _refreshPendingCount();
      await _refreshHeldCount();
      return;
    }

    var shouldFinalizeLoading = true;
    try {
      shouldFinalizeLoading = await _loadFromNetworkWithCacheFallback().timeout(
        _kPosOnlineLoadBudget,
      );
    } on TimeoutException {
      if (!mounted) return;
      await _bootstrapShellOfflineLoad();
      if (!mounted) return;
      setState(() => _loading = false);
      await _refreshPendingCount();
      await _refreshHeldCount();
      return;
    }

    if (!mounted) return;
    if (shouldFinalizeLoading) {
      setState(() => _loading = false);
      await _refreshPendingCount();
      await _refreshHeldCount();
    }
  }

  Map<String, dynamic> _businessSettingsToCacheMap(BusinessSettings s) {
    return {
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
    };
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

  bool _isProductByWeight(CatalogProduct p) =>
      (p.unit?.trim().toUpperCase() ?? '') == 'KG';

  CatalogProduct? _catalogByProductId(String productId) {
    for (final p in _all) {
      if (p.id == productId) return p;
    }
    return null;
  }

  String _gramsFromQuantity(String qty) {
    final q = PosCartQuantity.parse(qty);
    if (q <= 0) return '0';
    final grams = q * 1000;
    return grams.toStringAsFixed(1);
  }

  Future<void> _openWeightedAddSheet(
    CatalogProduct p, {
    PosCartLine? existing,
  }) async {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    final docPrice = PosSalePricing.documentUnitPrice(
      catalogPrice: p.price,
      catalogCurrency: p.currency,
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      pair: _fxPair,
    );
    String? funcPrice;
    final pc = p.currency.toUpperCase();
    if (pc == func.toUpperCase()) {
      funcPrice = p.price;
    } else if (pc == doc.toUpperCase()) {
      if (func.toUpperCase() == doc.toUpperCase()) {
        funcPrice = p.price;
      } else if (_fxPair != null) {
        final rate = _fxPair!.rate.rateQuotePerBase;
        funcPrice = _fxPair!.inverted
            ? MoneyStringMath.multiply(p.price, rate)
            : MoneyStringMath.divide(p.price, rate, fractionDigits: 2);
      }
    }
    if (docPrice == null || funcPrice == null) {
      _showCheckoutPanelMessage(
        'No se puede abrir modo peso: revisá moneda del ticket y tasa.',
        error: true,
      );
      return;
    }
    if (PosCartQuantity.parse(funcPrice) <= 0) {
      _showCheckoutPanelMessage(
        'Precio por kg no válido para este producto.',
        error: true,
      );
      return;
    }
    final fxDocPerFunc = func.toUpperCase() == doc.toUpperCase()
        ? '1'
        : MoneyStringMath.divide(docPrice, funcPrice, fractionDigits: 6);
    final res = await showPosWeightedAddSheet(
      context,
      productName: p.name,
      functionalCode: func,
      documentCode: doc,
      pricePerKgFunctional: funcPrice,
      pricePerKgDocument: docPrice,
      fxRateDocumentPerFunctional: fxDocPerFunc,
      initialGrams:
          existing?.displayGrams ??
          _gramsFromQuantity(existing?.quantity ?? '0'),
    );
    if (!mounted || res == null) return;
    _invalidateCheckoutIdempotency();
    final i = _cart.indexWhere((l) => l.productId == p.id);
    setState(() {
      final line = PosCartLine(
        productId: p.id,
        name: p.name,
        sku: p.sku,
        catalogUnitPrice: p.price,
        catalogCurrency: p.currency,
        documentUnitPrice: docPrice,
        documentCurrencyCode: doc,
        quantity: PosCartQuantity.normalize(res.quantityKg),
        isByWeight: true,
        displayGrams: res.displayGrams,
        pricePerKgFunctional: funcPrice,
        lineAmountFunctional: res.lineAmountFunctional,
        lineAmountDocument: res.lineAmountDocument,
      );
      if (i >= 0) {
        _cart[i] = line;
      } else {
        _cart.add(line);
      }
    });
    _search.clear();
    _searchFocus.unfocus();
    _showCartFeedback('${p.name} · ${res.displayGrams} g en el ticket');
  }

  Future<void> _addProductToCart(
    CatalogProduct p, {
    String addQty = '1',
  }) async {
    _invalidateCheckoutIdempotency();
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) {
      _showCheckoutPanelMessage(
        _contextError ?? 'No se cargó la configuración de la tienda.',
        error: true,
      );
      return;
    }
    final func = s.functionalCurrency.code;
    if (func.toUpperCase() != doc.toUpperCase() && _fxPair == null) {
      _showCheckoutPanelMessage(
        _fxLoadError ?? 'Falta tasa $func → $doc para vender en $doc.',
        error: true,
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
      _showCheckoutPanelMessage(
        'El producto está en ${p.currency}: solo se admite precio en $doc '
        'o en $func con tasa cargada.',
        error: true,
      );
      return;
    }
    if (_isProductByWeight(p)) {
      await _openWeightedAddSheet(p);
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
    _showCartFeedback('${p.name} × $add en el ticket');
  }

  Future<void> _openScanner() async {
    if (!BarcodeScannerScreen.isSupported) {
      _showCheckoutPanelMessage(
        'El escáner solo está disponible en Android e iOS.',
        error: true,
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final code = await BarcodeScannerScreen.open(context);
    if (!mounted || code == null || code.isEmpty) return;

    final p = _findByBarcode(_all, code);
    if (p != null) {
      if (_isProductByWeight(p)) {
        await _addProductToCart(p);
        return;
      }
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
                        unawaited(_addProductToCart(p, addQty: '$q'));
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
      _showCheckoutPanelMessage(
        'Ningún producto activo con código "$code". '
        'Buscá en Catálogo o cargá el código de barras en la ficha del producto.',
        error: true,
        duration: const Duration(seconds: 5),
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
      _showCheckoutPanelMessage(
        'Configuración de tienda no disponible.',
        error: true,
      );
      return;
    }
    final func = s.functionalCurrency.code;
    if (func.toUpperCase() != doc.toUpperCase() && _fxPair == null) {
      _showCheckoutPanelMessage(
        _fxLoadError ?? 'Definí la tasa del día antes de cobrar.',
        error: true,
      );
      return;
    }
    if (!_canChargeWithMixedPayments) {
      _showCheckoutPanelMessage(_remainingMixedLabel, error: true);
      return;
    }
    if (_mixedChangeFunctional > 0) {
      final proceed = await _showChangeSuggestionModal(
        functionalCode: func,
        documentCode: doc,
      );
      if (!proceed) return;
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
      payments: _buildPaymentsForPayload(
        functionalCode: func,
        documentCode: doc,
        saleFxSnapshot: _currentSaleFxSnapshot(
          functionalCode: func,
          documentCode: doc,
        ),
      ),
      clientSaleId: _pendingSaleId,
    );
    if (!_shellOnline) {
      await _queueSaleOffline(
        restBody,
        doc,
        queuedBecauseShellOffline: true,
      );
      return;
    }
    try {
      final res = await widget.salesApi.createSale(widget.storeId, restBody);
      if (!mounted) return;
      final totalDoc = _cartTotalDocument;
      var sid = res['id']?.toString().trim();
      if (sid == null || sid.isEmpty) {
        sid = _pendingSaleId ?? '';
      }
      if (sid.isNotEmpty && totalDoc != null) {
        final ticketNo = await widget.localPrefs
            .allocateLocalTicketDisplayCode();
        await widget.localPrefs.prependRecentSaleTicket(
          RecentSaleTicket(
            storeId: widget.storeId,
            saleId: sid,
            totalDocument: totalDoc,
            documentCurrencyCode: doc,
            // Calendario «hoy» del historial local usa día local; UTC podía caer en otro día.
            recordedAtIso: DateTime.now().toIso8601String(),
            status: RecentSaleTicket.statusSynced,
            displayCode: ticketNo,
          ),
        );
        if (!mounted) return;
      }
      final heldId = _activeHeldTicketId;
      setState(() {
        _cart.clear();
        _pendingSaleId = null;
        _checkoutBusy = false;
        _activeHeldTicketId = null;
      });
      _clearMixedPaymentInputs();
      if (heldId != null) {
        await widget.localPrefs.deleteHeldTicket(heldId);
        await _refreshHeldCount();
      }
      if (!mounted) return;
      _showCheckoutPanelMessage('Venta registrada.');
      unawaited(_runSyncCycle(silent: true, doPull: false));
    } on ApiError catch (e) {
      if (!mounted) return;
      final lower = e.userMessageForSupport.toLowerCase();
      final shouldQueueOffline =
          e.isRetryableSyncFailure ||
          lower.contains('timeout') ||
          lower.contains('socket') ||
          lower.contains('connection') ||
          lower.contains('network');
      if (shouldQueueOffline) {
        await _queueSaleOffline(restBody, doc);
        return;
      }
      setState(() => _checkoutBusy = false);
      final raw = e.userMessageForSupport;
      final msg = raw.contains('PAYMENTS_TOTAL_MISMATCH')
          ? 'El total pagado no cuadra con el total del ticket.'
          : raw.contains('PAYMENTS_MISSING_FX_SNAPSHOT')
          ? 'Falta la tasa (fxSnapshot) para convertir uno de los pagos.'
          : raw.contains('PAYMENTS_FX_PAIR_MISMATCH')
          ? 'La tasa enviada no coincide con el par de monedas del ticket.'
          : raw.contains('PAYMENTS_INVALID_AMOUNT')
          ? 'Hay un monto de pago inválido. Revisá los campos de cobro.'
          : raw;
      _logPosCheckoutApiFailure(e, msg);
      _showCheckoutPanelMessage(msg, error: true);
    } catch (e) {
      if (!mounted) return;
      if (isLikelyNetworkFailure(e)) {
        await _queueSaleOffline(restBody, doc);
        return;
      }
      setState(() => _checkoutBusy = false);
      _showCheckoutPanelMessage(e.toString(), error: true);
    }
  }

  Future<void> _queueSaleOffline(
    Map<String, dynamic> restBody,
    String doc, {
    bool queuedBecauseShellOffline = false,
  }) async {
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
    if (clientSid != null && clientSid.isNotEmpty && totalDoc != null) {
      final ticketNo = await widget.localPrefs.allocateLocalTicketDisplayCode();
      await widget.localPrefs.prependRecentSaleTicket(
        RecentSaleTicket(
          storeId: widget.storeId,
          saleId: clientSid,
          totalDocument: totalDoc,
          documentCurrencyCode: doc,
          recordedAtIso: DateTime.now().toIso8601String(),
          status: RecentSaleTicket.statusQueued,
          displayCode: ticketNo,
        ),
      );
      if (!mounted) return;
    }
    if (!mounted) return;
    final heldId = _activeHeldTicketId;
    setState(() {
      _cart.clear();
      _pendingSaleId = null;
      _checkoutBusy = false;
      _activeHeldTicketId = null;
    });
    _clearMixedPaymentInputs();
    if (heldId != null) {
      await widget.localPrefs.deleteHeldTicket(heldId);
      await _refreshHeldCount();
    }
    await _refreshPendingCount();
    if (!mounted) return;
    _showCheckoutPanelMessage(
      queuedBecauseShellOffline
          ? 'Modo offline: la venta quedó guardada en el dispositivo y se '
              'sincronizará cuando vuelvas a conectar con el servidor.'
          : 'Se perdió conexión con el servidor. La venta quedó en cola para '
              'sincronizar automáticamente al reconectar.',
      duration: const Duration(seconds: 6),
    );
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

  double _parseAmountInput(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return 0;
    return double.tryParse(normalized) ?? 0;
  }

  String _fmt2(double value) {
    if (value.isNaN || value.isInfinite) return '0.00';
    return value.toStringAsFixed(2);
  }

  double get _paymentFunctionalAmount => _appliedFunctionalPayment;

  double get _paymentFunctionalAppliedToSale {
    final total = _cartTotalFunctionalAmount;
    final paid = _paymentFunctionalAmount;
    if (paid <= 0) return 0;
    return paid > total ? total : paid;
  }

  double get _cartTotalDocumentAmount =>
      _parseAmountInput(_cartTotalDocument ?? '0');

  double get _functionalToDocumentRate {
    final func = _functionalCode;
    final doc = _selectedDocumentCurrency ?? '';
    if (func.isEmpty || doc.isEmpty) return 1;
    return _parseAmountInput(
      SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
        functionalCode: func,
        documentCode: doc,
        pair: _fxPair,
      ),
    );
  }

  double get _paymentFunctionalInDocument =>
      _paymentFunctionalAppliedToSale * _functionalToDocumentRate;

  double get _paymentTotalInDocument => _paymentFunctionalInDocument;

  bool get _hasAnyMixedPaymentInput => _paymentFunctionalAmount > 0;

  bool get _canChargeWithMixedPayments {
    if (!_hasAnyMixedPaymentInput) return true;
    return _paymentTotalInDocument + 0.009 >= _cartTotalDocumentAmount;
  }

  String get _remainingDocumentLabel {
    final doc = _selectedDocumentCurrency ?? '';
    final remaining = _cartTotalDocumentAmount - _paymentTotalInDocument;
    if (remaining <= 0) {
      return 'Resta en $doc: ${_fmt2(0)}';
    }
    return 'Falta por cobrar en $doc: ${_fmt2(remaining)}';
  }

  double get _cartTotalFunctionalAmount =>
      _parseAmountInput(_cartTotalFunctional ?? '0');

  double get _remainingFunctionalAmount {
    final rem = _cartTotalFunctionalAmount - _paymentFunctionalAmount;
    return rem > 0 ? rem : 0;
  }

  String get _remainingFunctionalLabel {
    final func = _functionalCode;
    return 'Resta en $func: ${_fmt2(_remainingFunctionalAmount)}';
  }

  String get _remainingMixedLabel =>
      '$_remainingFunctionalLabel · $_remainingDocumentLabel';

  /// Una línea compacta para el panel de cobro (pago mixto).
  String? get _mixedPaymentDetailLine {
    if (!_hasAnyMixedPaymentInput) return null;
    final func = _functionalCode;
    final doc = _selectedDocumentCurrency ?? '';
    final remDoc = _cartTotalDocumentAmount - _paymentTotalInDocument;
    final remDocClamped = remDoc < 0 ? 0.0 : remDoc;
    return '$func: ${_fmt2(_paymentFunctionalAmount)} · resta $doc: ${_fmt2(remDocClamped)}';
  }

  double get _mixedChangeFunctional {
    final change = _paymentFunctionalAmount - _cartTotalFunctionalAmount;
    return change > 0 ? change : 0;
  }

  Future<void> _openUsdPaymentModal() async {
    final func = _functionalCode;
    if (func.isEmpty) return;
    _paymentFunctionalCtrl.clear();
    final accepted = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pago en $func'),
        content: TextField(
          controller: _paymentFunctionalCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monto',
            hintText: '0.00',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final v = _parseAmountInput(_paymentFunctionalCtrl.text);
              Navigator.pop(ctx, v);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
    if (!mounted || accepted == null || accepted <= 0) return;
    setState(() {
      _appliedFunctionalPayment += accepted;
    });
    _showCheckoutPanelMessage(
      'Pago aplicado: ${_fmt2(accepted)} $func. $_remainingMixedLabel',
    );
  }

  Future<bool> _showChangeSuggestionModal({
    required String functionalCode,
    required String documentCode,
  }) async {
    final changeFunc = _mixedChangeFunctional;
    final changeDoc = changeFunc * _functionalToDocumentRate;
    final wholeFunc = changeFunc.floorToDouble();
    final fracFunc = changeFunc - wholeFunc;
    final fracDoc = fracFunc * _functionalToDocumentRate;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vuelto sugerido'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sobrante: ${_fmt2(changeFunc)} $functionalCode'),
            const SizedBox(height: 8),
            Text(
              documentCode.toUpperCase() == 'VES'
                  ? 'Vuelto en bolívares: ${_fmt2(changeDoc)} Bs.'
                  : 'Vuelto en moneda del ticket: ${_fmt2(changeDoc)} $documentCode',
            ),
            const SizedBox(height: 4),
            Text(
              documentCode.toUpperCase() == 'VES'
                  ? 'Vuelto mixto: ${_fmt2(wholeFunc)} $functionalCode + ${_fmt2(fracDoc)} Bs.'
                  : 'Vuelto mixto: ${_fmt2(wholeFunc)} $functionalCode + ${_fmt2(fracDoc)} $documentCode',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cobrar'),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Map<String, dynamic> _currentSaleFxSnapshot({
    required String functionalCode,
    required String documentCode,
  }) {
    final rate = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: functionalCode,
      documentCode: documentCode,
      pair: _fxPair,
    );
    final rawDate = _fxPair?.rate.effectiveDate.trim() ?? '';
    final date = rawDate.isEmpty
        ? DateTime.now().toUtc().toIso8601String().substring(0, 10)
        : (rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate);
    return <String, dynamic>{
      'baseCurrencyCode': functionalCode.trim(),
      'quoteCurrencyCode': documentCode.trim(),
      'rateQuotePerBase': rate,
      'effectiveDate': date,
    };
  }

  List<Map<String, dynamic>>? _buildPaymentsForPayload({
    required String functionalCode,
    required String documentCode,
    required Map<String, dynamic> saleFxSnapshot,
  }) {
    final payments = <Map<String, dynamic>>[];
    if (_paymentFunctionalAmount > 0) {
      final fx = <String, dynamic>{...saleFxSnapshot};
      payments.add({
        'method': 'CASH_${functionalCode.toUpperCase()}',
        'amount': _fmt2(_paymentFunctionalAppliedToSale),
        'currencyCode': functionalCode.toUpperCase(),
        if (functionalCode.toUpperCase() != documentCode.toUpperCase())
          'fxSnapshot': fx,
      });
    }
    return payments.isEmpty ? null : payments;
  }

  void _clearMixedPaymentInputs() {
    _paymentFunctionalCtrl.clear();
    _appliedFunctionalPayment = 0;
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
    found.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (found.length > 100) {
      return found.sublist(0, 100);
    }
    return found;
  }

  String? _resolvedImageUrl(String? raw) => resolveProductImageUrl(raw);

  String? _cartImageUrlForProductId(String productId) {
    for (final p in _all) {
      if (p.id == productId) return _resolvedImageUrl(p.imageUrl);
    }
    return null;
  }

  /// Teléfono / layout estrecho: evita sugerencias inline y depender solo de `viewInsets`
  /// (en muchos Android el IME reporta 0 o tarde → el panel «Moneda del ticket» sube al buscador).
  bool _isCompactPosLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide < 600;

  /// En móvil, al enfocar el buscador ocultamos el panel de cobro para que no compita
  /// por altura con el ticket y no quede pegado al input.
  bool _hideCheckoutWhileSearchFocused(BuildContext context) =>
      _isCompactPosLayout(context) && _searchFocus.hasFocus;

  /// Panel modal a pantalla completa en el Stack raíz (no dentro del `Expanded`).
  bool _keyboardSuggestionOverlayActive(BuildContext context) {
    if (!_searchFocus.hasFocus) return false;
    if (_loading || _error != null) return false;
    if (_search.text.trim().isEmpty) return false;
    if (_isCompactPosLayout(context)) return true;
    return MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  bool _showInlineSearchSuggestions(BuildContext context) {
    if (_search.text.trim().isEmpty || _loading || _error != null) {
      return false;
    }
    if (_isCompactPosLayout(context)) return false;
    return !_keyboardSuggestionOverlayActive(context);
  }

  void _dismissSearchSuggestionOverlay() {
    _searchFocus.unfocus();
  }

  double _posSearchOverlayTopInset(BuildContext stackDescendantContext) {
    final anchorCtx = _posSearchAnchorKey.currentContext;
    if (anchorCtx == null) return 168;
    final anchorBox = anchorCtx.findRenderObject() as RenderBox?;
    final stackBox = stackDescendantContext
        .findAncestorRenderObjectOfType<RenderStack>();
    if (anchorBox == null ||
        stackBox == null ||
        !anchorBox.hasSize ||
        !anchorBox.attached) {
      return 168;
    }
    final a = anchorBox.localToGlobal(Offset.zero);
    final s = stackBox.localToGlobal(Offset.zero);
    return (a.dy - s.dy + anchorBox.size.height).clamp(0.0, 8000.0);
  }

  Widget _buildSearchSuggestionsScrollable() {
    if (_searchPreview.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Sin coincidencias',
            style: TextStyle(color: PosSaleUi.textMuted),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _searchPreview.length,
      separatorBuilder: (context, i) =>
          const Divider(height: 1, color: PosSaleUi.divider),
      itemBuilder: (context, i) {
        final p = _searchPreview[i];
        final docLbl = _documentPriceLabel(p);
        final bc = p.barcode?.trim();
        return PosSaleSearchResultTile(
          product: p,
          primaryLine: docLbl ?? '${p.price} ${p.currency}',
          secondaryLine: [
            'SKU ${p.sku}',
            if (bc != null && bc.isNotEmpty) bc,
          ].join(' · '),
          imageUrl: _resolvedImageUrl(p.imageUrl),
          onTap: () => unawaited(_addProductToCart(p)),
        );
      },
    );
  }

  Widget _buildKeyboardSuggestionOverlay(
    BuildContext context,
    BoxConstraints stackConstraints,
  ) {
    final mq = MediaQuery.of(context);
    final kb = mq.viewInsets.bottom;
    final safeBottom = mq.padding.bottom;
    final liftBottom = kb > 0 ? kb : safeBottom;
    final top = _posSearchOverlayTopInset(context);
    final availH = stackConstraints.maxHeight - top - liftBottom;
    if (availH < 100) return const SizedBox.shrink();
    final panelH = min(480.0, max(220.0, availH * 0.52));

    return Padding(
      padding: EdgeInsets.only(top: top, bottom: liftBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissSearchSuggestionOverlay,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ),
          Material(
            color: PosSaleUi.searchSuggestionsSurface,
            elevation: 16,
            shadowColor: Colors.black,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: double.infinity,
              height: panelH,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Productos',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: PosSaleUi.text,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: _dismissSearchSuggestionOverlay,
                          icon: const Icon(
                            Icons.close,
                            color: PosSaleUi.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: PosSaleUi.divider),
                  Expanded(child: _buildSearchSuggestionsScrollable()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _bumpLine(int index, double delta) {
    final line = _cart[index];
    if (line.isByWeight) {
      final p = _catalogByProductId(line.productId);
      if (p != null) {
        unawaited(_openWeightedAddSheet(p, existing: line));
      }
      return;
    }
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
    if (line.isByWeight) {
      final p = _catalogByProductId(line.productId);
      if (p != null) {
        await _openWeightedAddSheet(p, existing: line);
      }
      return;
    }
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
      _activeHeldTicketId = null;
    });
    _clearMixedPaymentInputs();
  }

  void _simulateRandomScan() {
    final active = _all.where((p) => p.active).toList();
    if (active.isEmpty) {
      _showCheckoutPanelMessage('No hay productos en catálogo.', error: true);
      return;
    }
    final p = active[Random().nextInt(active.length)];
    unawaited(_addProductToCart(p, addQty: '1'));
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
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          bottom: false,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(context).bottom,
                ),
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
                    padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          _pendingQueueServerAvailableHint
                              ? Icons.wifi_find
                              : Icons.cloud_upload_outlined,
                          color: PosSaleUi.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _pendingQueueServerAvailableHint
                                    ? 'Modo online disponible — conectar'
                                    : '$_pendingSyncCount en cola',
                                style: const TextStyle(
                                  color: PosSaleUi.text,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (_pendingQueueServerAvailableHint)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'En Inicio desactivá «Poner offline» para '
                                    'sincronizar ($_pendingSyncCount pendiente'
                                    '${_pendingSyncCount == 1 ? '' : 's'}).',
                                    style: TextStyle(
                                      color: PosSaleUi.text.withValues(
                                        alpha: 0.85,
                                      ),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                            ],
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
              KeyedSubtree(
                key: _posSearchAnchorKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PosSaleSearchBlock(
                      controller: _search,
                      focusNode: _searchFocus,
                      onScanTap: _openScanner,
                      onScanLongPress: _simulateRandomScan,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Text(
                          _fxLoadError!,
                          style: const TextStyle(
                            color: PosSaleUi.error,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                      builder: (context, constraints) {
                        final idealSearchH =
                            _kSearchRowExtent * _kSearchVisibleRows +
                            (_kSearchVisibleRows - 1);
                        // Share Expanded between suggestions and ticket: reserve a slice for the
                        // cart block, use the remainder for up to 5 result rows (no fixed % cap
                        // that only showed ~2 rows when plenty of space was left).
                        final cartReserve =
                            (constraints.maxHeight *
                                    _kSearchCartReserveFraction)
                                .clamp(
                                  _kSearchCartReserveMin,
                                  _kSearchCartReserveMax,
                                );
                        final searchCap = min(
                          idealSearchH,
                          max(0.0, constraints.maxHeight - cartReserve),
                        ).clamp(0.0, constraints.maxHeight);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_showInlineSearchSuggestions(context)) ...[
                              Material(
                                color: PosSaleUi.searchSuggestionsSurface,
                                elevation: 3,
                                child: SizedBox(
                                  height: searchCap,
                                  child: _buildSearchSuggestionsScrollable(),
                                ),
                              ),
                            ],
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
                                              style: const TextStyle(
                                                color: PosSaleUi.text,
                                              ),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            6,
                                            16,
                                            4,
                                          ),
                                          child: Row(
                                            children: [
                                              Text(
                                                'TICKET ACTUAL',
                                                style: PosSaleUi.titleCart(
                                                  context,
                                                ),
                                              ),
                                              const Spacer(),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: PosSaleUi.primary,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  _cartQtySummary(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
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
                                                    padding:
                                                        const EdgeInsets.all(
                                                          32,
                                                        ),
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .shopping_cart_outlined,
                                                          size: 56,
                                                          color: PosSaleUi
                                                              .textFaint,
                                                        ),
                                                        const SizedBox(
                                                          height: 16,
                                                        ),
                                                        const Text(
                                                          'El ticket está vacío',
                                                          style: TextStyle(
                                                            color: PosSaleUi
                                                                .textMuted,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        Text(
                                                          'Buscá un producto o escaneá el código.',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            color: PosSaleUi
                                                                .textFaint,
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
                                                    separatorBuilder:
                                                        (context, i) =>
                                                            const Divider(
                                                              height: 1,
                                                              color: PosSaleUi
                                                                  .divider,
                                                            ),
                                                    itemBuilder: (context, i) {
                                                      final l = _cart[i];
                                                      final uf =
                                                          _functionalFromDocument(
                                                            l.documentUnitPrice,
                                                          );
                                                      final lf =
                                                          _functionalFromDocument(
                                                            l.lineTotalDocument,
                                                          );
                                                      return PosSaleCartLineTile(
                                                        line: l,
                                                        imageUrl:
                                                            _cartImageUrlForProductId(
                                                              l.productId,
                                                            ),
                                                        unitFunctional: uf,
                                                        lineTotalFunctional: lf,
                                                        functionalCode: func,
                                                        documentCode:
                                                            doc ??
                                                            l.documentCurrencyCode,
                                                        onMinus: () =>
                                                            _bumpLine(i, -1),
                                                        onPlus: () =>
                                                            _bumpLine(i, 1),
                                                        onQtyTap: () =>
                                                            _onLineQtyTap(i),
                                                        onDismissed: () =>
                                                            _removeLineByProductId(
                                                              l.productId,
                                                            ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
              ),
              if (!_loading &&
                  _error == null &&
                  doc != null &&
                  !_hideCheckoutWhileSearchFocused(context))
                PosSaleCheckoutPanel(
                  functionalCode: func,
                  documentCode: doc,
                  functionalTotalLabel: _posCurrencyLabel(func),
                  documentTotalLabel: _posCurrencyLabel(doc),
                  totalFunctional: tf,
                  totalDocument: td,
                  itemsSummary:
                      '${_cart.length} líneas · ${_cartQtySummary()} u.',
                  cartNotEmpty: !cartEmpty,
                  cartFeedback: _cartFeedback,
                  cartFeedbackIsError: _cartFeedbackIsError,
                  onOpenMixedPayment: _openUsdPaymentModal,
                  onClearMixedPayment: _appliedFunctionalPayment > 0
                      ? () => setState(_clearMixedPaymentInputs)
                      : null,
                  mixedPaymentDetailLine: _mixedPaymentDetailLine,
                  canChargeWithPayments: _canChargeWithMixedPayments,
                  onClear: _clearCart,
                  onCharge: _onCheckout,
                  chargeBusy: _checkoutBusy,
                  onPutOnHold: _putCartOnHold,
                  onOpenHeldTickets: _openHeldTicketsList,
                  heldTicketsCount: _heldTicketsCount,
                  onDiscount: () {
                    _showCheckoutPanelMessage('Descuentos: próximamente.');
                  },
                  currencySelector: _documentCurrencyOptions.length > 1
                      ? Row(
                          children: [
                            const Text(
                              'Moneda ticket',
                              style: TextStyle(
                                color: PosSaleUi.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                isDense: true,
                                isExpanded: true,
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
                                  fontSize: 12,
                                ),
                                items: _documentCurrencyOptions
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(
                                          c,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _onDocumentCurrencyChanged,
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
                  ],
                ),
              ),
              if (_keyboardSuggestionOverlayActive(context))
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (ctx, constraints) =>
                        _buildKeyboardSuggestionOverlay(ctx, constraints),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
