import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderStack;

import '../../core/api/cash_sessions_api.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/payment_methods_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/config/app_config.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/active_pos_cart_draft.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/held_ticket.dart';
import '../../core/models/recent_sale_ticket.dart';
import '../../core/models/inventory_line.dart';
import '../../core/models/payment_method.dart';
import '../../core/models/pos_cart_line.dart';
import '../../core/network/product_image_url.dart';
import '../../core/pos/catalog_unit_cost_functional.dart';
import '../../core/pos/money_string_math.dart';
import '../../core/pos/pos_cash_advance.dart';
import '../../core/pos/pos_sale_pricing.dart';
import '../../core/pos/pos_stock_assessment.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/pos/recent_sale_functional_enricher.dart';
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/text/search_text_match.dart';
import '../../core/sync/device_hydrate_sync.dart';
import '../../core/sync/pending_sale_entry.dart';
import '../../core/sync/sync_cycle.dart';
import '../shell/shell_online_scope.dart';
import 'barcode_scanner_screen.dart';
import 'pos_cart_quantity.dart';
import 'pos_held_tickets_ui.dart';
import 'pos_payment_sheet.dart';
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
    this.cashSessionsApi,
    this.paymentMethodsApi,
    this.onRequestExit,
    this.onHydrateDevice,
  });

  final String storeId;
  final ProductsApi productsApi;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final SalesApi salesApi;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final LocalPrefs localPrefs;
  final CashSessionsApi? cashSessionsApi;
  final PaymentMethodsApi? paymentMethodsApi;

  /// Si no es null (p. ej. módulo Ventas), muestra atrás en la barra superior.
  final VoidCallback? onRequestExit;
  final DeviceHydrateCallback? onHydrateDevice;

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen>
    with WidgetsBindingObserver {
  static const double _kSearchRowExtent = 72;
  static const int _kSearchVisibleRows = 5;

  /// Min vertical space kept for ticket + list; search suggestions use the rest (up to 5 rows).
  static const double _kSearchCartReserveMin = 96;
  static const double _kSearchCartReserveMax = 168;
  static const double _kSearchCartReserveFraction = 0.26;

  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _paymentFunctionalCtrl = TextEditingController();
  final List<PosAppliedPayment> _appliedPayments = [];
  List<PaymentMethod> _paymentMethods = [];
  List<CatalogProduct> _all = [];
  final List<PosCartLine> _cart = [];
  List<InventoryLine> _inventoryCache = [];
  bool _catalogLikelyFresh = true;
  bool _checkoutStockConflict = false;
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
  Timer? _cartDraftPersistTimer;

  String? _cartFeedback;
  bool _cartFeedbackIsError = false;
  Timer? _cartFeedbackTimer;

  int _heldTicketsCount = 0;
  String? _activeHeldTicketId;
  bool _shellOnline = true;
  bool _shellManualForceOffline = false;
  bool _shellBackendReachable = true;
  /// Evita saltar [_load] en el primer [didChangeDependencies]: el estado local
  /// (`_shellOnline == true`) coincidía con el shell antes de que exista un cambio
  /// real y el POS quedaba en `_loading` eterno.
  bool _shellScopeBound = false;

  /// Borde inferior del bloque buscador (+ aviso FX): el overlay de sugerencias empieza debajo.
  final GlobalKey _posSearchAnchorKey = GlobalKey(debugLabel: 'pos_search_anchor');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _cartDraftPersistTimer?.cancel();
      unawaited(_persistActiveCartDraftNow());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = context.dependOnInheritedWidgetOfExactType<ShellOnlineScope>();
    final nextOnline = scope?.isOnline ?? true;
    final nextManual = scope?.manualForceOffline ?? false;
    final nextBackend = scope?.backendReachable ?? true;
    final unchanged = _shellScopeBound &&
        _shellOnline == nextOnline &&
        _shellManualForceOffline == nextManual &&
        _shellBackendReachable == nextBackend;
    if (unchanged) {
      return;
    }
    _shellScopeBound = true;
    _shellOnline = nextOnline;
    _shellManualForceOffline = nextManual;
    _shellBackendReachable = nextBackend;
    debugPrint(
      '[POS load] didChangeDependencies → _load() '
      'online=$nextOnline manualOffline=$nextManual backendOk=$nextBackend',
    );
    unawaited(_load());
  }

  void _onCatalogInvalidated() {
    if (!mounted) return;
    // Nunca reabrir spinner de POS por un pull: refresco silencioso.
    unawaited(_refreshCatalogSilent());
    unawaited(_refreshInventoryCacheSilent());
  }

  /// Catálogo solo desde cache local (sin GET al backend).
  Future<void> _refreshCatalogSilent() async {
    final cached = await widget.localPrefs.loadCatalogProductsCache();
    if (!mounted) return;
    if (cached.isEmpty) return;
    final active = cached.where((p) => p.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _all = active.isNotEmpty ? active : cached;
      if (_error != null && _all.isNotEmpty) _error = null;
    });
  }

  Future<void> _refreshPendingCount() async {
    final n = await widget.localPrefs.countPendingSyncOpsForStore(
      widget.storeId,
    );
    if (mounted) setState(() => _pendingSyncCount = n);
  }

  Future<void> _refreshInventoryCacheSilent() async {
    try {
      final inv = await widget.localPrefs.loadInventoryCache(widget.storeId);
      final stale = await widget.localPrefs.isCatalogLikelyStale();
      if (!mounted) return;
      setState(() {
        _inventoryCache = inv;
        _catalogLikelyFresh = !stale;
      });
    } catch (_) {}
  }

  Future<bool> _guardStockPoliciesBeforeCheckout() async {
    await _refreshInventoryCacheSilent();
    if (!mounted) return false;
    final assessment = assessPosCartStock(
      cart: _cart,
      catalog: _all,
      inventory: _inventoryCache,
      settings: _settings,
      catalogLikelyFresh: _catalogLikelyFresh,
    );
    _checkoutStockConflict = false;

    final allowNeg = _settings?.allowNegativeStockAtPos ?? true;
    final warn = _settings?.warnOnNegativeStock ?? true;
    final blockRestricted =
        _settings?.blockRestrictedProductsWithoutStock ?? true;

    if (assessment.hasRestrictedInsufficient) {
      if (blockRestricted) {
        final pinOk = await _askSupervisorPinForRestrictedStock(
          assessment.lines.where((l) => l.willGoNegative && l.isRestricted),
        );
        if (!pinOk) return false;
        _checkoutStockConflict = true;
      } else if (warn) {
        final cont = await _askContinueNegativeStock(
          assessment.lines.where((l) => l.willGoNegative),
          restricted: true,
        );
        if (!cont) return false;
        _checkoutStockConflict = true;
      } else {
        _checkoutStockConflict = true;
      }
    }

    final policyBlocked = assessment.lines
        .where((l) => l.willGoNegative && !l.isRestricted && !allowNeg)
        .toList();
    if (policyBlocked.isNotEmpty) {
      final names = policyBlocked.map((l) => l.productName).join(', ');
      _showCheckoutPanelMessage(
        'Stock insuficiente y la tienda no permite negativo: $names',
        error: true,
        duration: const Duration(seconds: 5),
      );
      return false;
    }

    if (assessment.hasWarnableNegative) {
      if (warn) {
        final cont = await _askContinueNegativeStock(
          assessment.lines.where((l) => l.willGoNegative && !l.isRestricted),
        );
        if (!cont) return false;
        _checkoutStockConflict = true;
      } else {
        _checkoutStockConflict = true;
        _showCheckoutPanelMessage(
          'Aviso: algunas líneas pueden dejar stock negativo.',
          error: false,
          duration: const Duration(seconds: 3),
        );
      }
    }

    return true;
  }

  Future<bool> _askSupervisorPinForRestrictedStock(
    Iterable<PosStockLineAssessment> lines,
  ) async {
    final detail = lines
        .map(
          (l) =>
              '• ${l.productName}: pide ${l.requestedQty} / hay ${l.availableLabel}',
        )
        .join('\n');
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: PosSaleUi.surface2,
        title: const Text(
          'Producto restringido sin stock',
          style: TextStyle(color: PosSaleUi.text),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                detail,
                style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              const Text(
                'PIN de supervisor (solo app):',
                style: TextStyle(color: PosSaleUi.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(color: PosSaleUi.text),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: PosSaleUi.surface3,
                ),
                onSubmitted: (_) {
                  Navigator.pop(ctx, AppConfig.adminPinMatches(ctrl.text));
                },
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
            onPressed: () =>
                Navigator.pop(ctx, AppConfig.adminPinMatches(ctrl.text)),
            child: const Text('Autorizar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (ok != true) {
      _showCheckoutPanelMessage(
        'Se necesita PIN de supervisor para productos restringidos sin stock.',
        error: true,
      );
      return false;
    }
    return true;
  }

  Future<bool> _askContinueNegativeStock(
    Iterable<PosStockLineAssessment> lines, {
    bool restricted = false,
  }) async {
    final detail = lines
        .map(
          (l) =>
              '• ${l.productName}: pide ${l.requestedQty} / hay ${l.availableLabel}',
        )
        .join('\n');
    final cont = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PosSaleUi.surface2,
        title: Text(
          restricted
              ? 'Stock insuficiente (restringido)'
              : 'Stock insuficiente',
          style: const TextStyle(color: PosSaleUi.text),
        ),
        content: Text(
          '$detail\n\n¿Continuar y registrar incidencia?',
          style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    return cont == true;
  }

  /// [doPull]: actualiza watermark con `GET /sync/pull`; [doFlush]: envía cola mixta.
  Future<void> _runSyncCycle({bool silent = false, bool doPull = true}) async {
    debugPrint(
      '[POS sync] tap/start silent=$silent doPull=$doPull '
      'shellOnline=$_shellOnline flushBusy=$_flushBusy store=${widget.storeId}',
    );
    if (!_shellOnline) {
      debugPrint('[POS sync] abort: no shell online');
      if (!silent && mounted) {
        _showCheckoutPanelMessage(
          'Modo offline: la sincronización se hará al volver online.',
          error: false,
          duration: const Duration(seconds: 2),
        );
      }
      return;
    }
    if (_flushBusy) {
      debugPrint('[POS sync] abort: ya hay un sync en curso');
      return;
    }

    final hydrate = widget.onHydrateDevice;
    if (!silent && hydrate != null && doPull) {
      setState(() => _flushBusy = true);
      try {
        final result = await hydrate(requireEmptyQueue: false);
        if (!mounted) return;
        await _bootstrapShellOfflineLoad();
        await _refreshPendingCount();
        await _refreshInventoryCacheSilent();
        await _refreshCatalogSilent();
        await _loadPaymentMethodsFromCache();
        await _refreshPaymentMethods();
        _showCheckoutPanelMessage(
          result.userMessage,
          error: !result.ok,
          duration: Duration(seconds: result.ok ? 3 : 6),
        );
      } catch (e) {
        if (mounted) {
          _showCheckoutPanelMessage('$e', error: true);
        }
      } finally {
        if (mounted) setState(() => _flushBusy = false);
      }
      return;
    }
    final pendingN = await widget.localPrefs.countPendingSyncOpsForStore(
      widget.storeId,
    );
    debugPrint('[POS sync] pendingOps=$pendingN');
    if (pendingN == 0 && !doPull) {
      debugPrint('[POS sync] skip: sin pendientes y doPull=false');
      return;
    }

    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;

    setState(() => _flushBusy = true);
    try {
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
      debugPrint(
        '[POS sync] ok pullErr=${cycle.pullError} pullOps=${cycle.pullOpsReceived} '
        'flushSent=${cycle.flush.sentCount} removed=${cycle.flush.removedCount}',
      );

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
      }
      final flushMsg = r.apiMessage?.trim();
      if (!silent &&
          flushMsg != null &&
          flushMsg.isNotEmpty &&
          (pendingN > 0 || r.hadManualReviewFailure)) {
        final suffix = r.hadManualReviewFailure
            ? '\nRequiere revisión manual o nueva opId si el servidor rechazó la operación.'
            : (r.hadRetryableFailure ? '\nSe reintentará automáticamente.' : '');
        _showCheckoutPanelMessage(
          '$flushMsg$suffix',
          error: r.hadManualReviewFailure || r.hadRetryableFailure,
          duration: Duration(seconds: r.hadManualReviewFailure ? 12 : 6),
        );
      }
    } catch (e, st) {
      debugPrint('[POS sync] EXCEPCIÓN: $e');
      debugPrint('$st');
      if (!silent && mounted) {
        _showCheckoutPanelMessage('Sync: $e', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _flushBusy = false);
      }
      await _refreshPendingCount();
      if (_shellOnline) {
        await _refreshPaymentMethods();
      }
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

  void _showCheckoutPanelMessage(
    String message, {
    bool error = false,
    Duration? duration,
  }) {
    _cartFeedbackTimer?.cancel();
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
    WidgetsBinding.instance.removeObserver(this);
    _cartDraftPersistTimer?.cancel();
    unawaited(_persistActiveCartDraftNow());
    _cartFeedbackTimer?.cancel();
    _pendingCountPoll?.cancel();
    widget.catalogInvalidationBus.removeListener(_onCatalogInvalidated);
    _search.dispose();
    _searchFocus.dispose();
    _paymentFunctionalCtrl.dispose();
    super.dispose();
  }

  void _schedulePersistActiveCartDraft() {
    _cartDraftPersistTimer?.cancel();
    _cartDraftPersistTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistActiveCartDraftNow());
    });
  }

  Future<void> _persistActiveCartDraftNow() async {
    try {
      _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
      final terminal = _terminal;
      final doc = _selectedDocumentCurrency;
      if (terminal == null) return;
      if (_cart.isEmpty || doc == null || doc.trim().isEmpty) {
        await widget.localPrefs.clearActivePosCartDraft(
          storeId: widget.storeId,
          deviceId: terminal.deviceId,
        );
        return;
      }
      await widget.localPrefs.saveActivePosCartDraft(
        ActivePosCartDraft(
          storeId: widget.storeId,
          deviceId: terminal.deviceId,
          documentCurrencyCode: doc,
          lines: _cart.map(_cloneCartLine).toList(),
          updatedAtIso: DateTime.now().toUtc().toIso8601String(),
          activeHeldTicketId: _activeHeldTicketId,
        ),
      );
    } catch (e, st) {
      debugPrint('[POS cart draft] persist failed: $e\n$st');
    }
  }

  Future<void> _clearActiveCartDraftNow() async {
    _cartDraftPersistTimer?.cancel();
    try {
      _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
      final terminal = _terminal;
      if (terminal == null) return;
      await widget.localPrefs.clearActivePosCartDraft(
        storeId: widget.storeId,
        deviceId: terminal.deviceId,
      );
    } catch (e, st) {
      debugPrint('[POS cart draft] clear failed: $e\n$st');
    }
  }

  Future<void> _restoreActiveCartDraftIfNeeded() async {
    if (!mounted || _cart.isNotEmpty || _settings == null) return;
    try {
      _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
      if (!mounted || _terminal == null) return;
      final draft = await widget.localPrefs.loadActivePosCartDraft(
        storeId: widget.storeId,
        deviceId: _terminal!.deviceId,
      );
      if (!mounted || draft == null || draft.lines.isEmpty) return;
      final docCode = _matchDocumentCurrencyOption(draft.documentCurrencyCode);
      if (docCode == null) {
        debugPrint(
          '[POS cart draft] moneda ${draft.documentCurrencyCode} no disponible',
        );
        return;
      }
      setState(() {
        _selectedDocumentCurrency = docCode;
        _cart
          ..clear()
          ..addAll(draft.lines.map(_cloneCartLine));
        _activeHeldTicketId = draft.activeHeldTicketId;
        _invalidateCheckoutIdempotency();
      });
      await _reloadFxForDocumentCurrency(rebuildDocumentLinePrices: false);
    } catch (e, st) {
      debugPrint('[POS cart draft] restore failed: $e\n$st');
    }
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

  Future<void> _reloadFxForDocumentCurrency({
    bool rebuildDocumentLinePrices = true,
  }) async {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    // En refresh silencioso no vaciar la tasa en uso (evitar flash que bloquee cobro).
    if (rebuildDocumentLinePrices) {
      setState(() {
        _fxLoadError = null;
        _fxPair = null;
      });
    }
    if (func.toUpperCase() == doc.toUpperCase()) {
      if (rebuildDocumentLinePrices) {
        _rebuildCartDocumentPrices();
      }
      if (mounted) setState(() {});
      return;
    }
    // Tasa solo desde cache: se actualiza con Sincronizar / apertura / cierre.
    await _applyFxFromPrefsCacheOnly();
    if (rebuildDocumentLinePrices) {
      _rebuildCartDocumentPrices();
    }
    if (mounted) setState(() {});
  }

  /// Reconvierte el ticket a la moneda documento / FX actuales **sin** tomar
  /// precios nuevos del catálogo (precio congelado al agregar).
  void _rebuildCartDocumentPrices() {
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    final next = <PosCartLine>[];
    for (final old in _cart) {
      if (old.isByWeight) {
        final docPrice = PosSalePricing.documentUnitPrice(
          catalogPrice: old.catalogUnitPrice,
          catalogCurrency: old.catalogCurrency,
          documentCurrencyCode: doc,
          functionalCurrencyCode: func,
          pair: _fxPair,
        );
        if (docPrice == null) continue;
        final funcPrice = old.pricePerKgFunctional;
        final qty = old.quantity;
        final lineFunc = (funcPrice != null &&
                PosCartQuantity.parse(funcPrice) > 0)
            ? MoneyStringMath.multiply(funcPrice, qty)
            : old.lineAmountFunctional;
        next.add(
          PosCartLine(
            productId: old.productId,
            name: old.name,
            sku: old.sku,
            catalogUnitPrice: old.catalogUnitPrice,
            catalogCurrency: old.catalogCurrency,
            documentUnitPrice: docPrice,
            documentCurrencyCode: doc,
            quantity: qty,
            isByWeight: true,
            displayGrams: old.displayGrams,
            pricePerKgFunctional: funcPrice,
            lineAmountFunctional: lineFunc,
            lineAmountDocument: MoneyStringMath.multiply(docPrice, qty),
          ),
        );
        continue;
      }

      if (old.isCashAdvance) {
        var advanceBase = old.advanceBaseDocument;
        if (advanceBase != null &&
            PosCashAdvance.isPositiveAmount(advanceBase) &&
            old.documentCurrencyCode.toUpperCase() != doc.toUpperCase()) {
          advanceBase = PosSalePricing.documentUnitPrice(
            catalogPrice: advanceBase,
            catalogCurrency: old.documentCurrencyCode,
            documentCurrencyCode: doc,
            functionalCurrencyCode: func,
            pair: _fxPair,
          );
        }
        if (advanceBase == null ||
            !PosCashAdvance.isPositiveAmount(advanceBase)) {
          continue;
        }
        final fee = PosCashAdvance.feeFromAdvanceAmount(advanceBase);
        final total =
            PosCashAdvance.totalChargeFromAdvanceAmount(advanceBase);
        if (!PosCashAdvance.isPositiveAmount(fee) ||
            !PosCashAdvance.isPositiveAmount(total)) {
          continue;
        }
        next.add(
          PosCartLine(
            productId: old.productId,
            name: old.name,
            sku: old.sku,
            catalogUnitPrice: total,
            catalogCurrency: doc,
            documentUnitPrice: total,
            documentCurrencyCode: doc,
            quantity: '1',
            isCashAdvance: true,
            advanceBaseDocument: advanceBase,
          ),
        );
        continue;
      }

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
    _schedulePersistActiveCartDraft();
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
    await _clearActiveCartDraftNow();
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
    _schedulePersistActiveCartDraft();
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
        await _clearActiveCartDraftNow();
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
        if (_cart.isEmpty) {
          _selectedDocumentCurrency = doc;
        }
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
    await _loadPaymentMethodsFromCache();
  }

  Future<void> _loadPaymentMethodsFromCache() async {
    final cached = await widget.localPrefs.loadPaymentMethodsCache(
      widget.storeId,
    );
    if (!mounted || cached.isEmpty) return;
    setState(() => _paymentMethods = cached);
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

  Future<void> _refreshPaymentMethods() async {
    final api = widget.paymentMethodsApi;
    if (api == null) {
      await _loadPaymentMethodsFromCache();
      return;
    }
    if (!_shellOnline) {
      await _loadPaymentMethodsFromCache();
      return;
    }
    try {
      final list = await api.listActive(widget.storeId);
      if (!mounted) return;
      if (list.isEmpty) {
        debugPrint(
          '[POS] payment-methods: servidor devolvió 0 activos '
          '(store=${widget.storeId})',
        );
        await _loadPaymentMethodsFromCache();
        return;
      }
      await widget.localPrefs.savePaymentMethodsCache(widget.storeId, list);
      setState(() => _paymentMethods = list);
      debugPrint('[POS] payment-methods loaded: ${list.length}');
    } catch (e) {
      debugPrint('[POS] payment-methods load failed: $e');
      await _loadPaymentMethodsFromCache();
    }
  }

  List<PaymentMethod> get _activePaymentMethods {
    if (_paymentMethods.isNotEmpty) return _paymentMethods;
    final func = _functionalCode;
    if (func.isEmpty) return const [];
    return [PaymentMethod.fallbackCash(func)];
  }

  /// Hay catálogo + settings en memoria/cache para vender sin esperar red.
  bool get _hasUsablePosLocalData =>
      _all.isNotEmpty && _settings != null && _selectedDocumentCurrency != null;

  Future<void> _load() async {
    debugPrint(
      '[POS load] start online=$_shellOnline loadingWas=$_loading '
      'hasLocal=$_hasUsablePosLocalData',
    );

    // Solo cache local: productos/precios/tasa vienen de Sincronizar (o apertura/cierre).
    await _bootstrapShellOfflineLoad();
    if (!mounted) return;

    final usable = _hasUsablePosLocalData ||
        (_all.isNotEmpty && _settings != null);

    setState(() {
      _loading = false;
      if (!usable) {
        _error =
            'Sin datos locales. Tocá Sincronizar o sincronizá desde Inicio.';
      } else if (_all.isEmpty) {
        _error = 'Sin productos en caché. Sincronizá desde Inicio.';
      } else {
        _error = null;
      }
    });
    await _restoreActiveCartDraftIfNeeded();
    await _refreshPendingCount();
    await _refreshHeldCount();
    unawaited(_refreshInventoryCacheSilent());
    if (_shellOnline) {
      unawaited(_refreshPaymentMethods());
    }
    debugPrint('[POS load] painted from cache (payment-methods if online)');
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

  /// Precio por kg en moneda funcional (líneas a peso), alineado con [_openWeightedAddSheet].
  String? _tryPerKgFunctionalPrice(
    CatalogProduct p,
    String functionalCode,
    String documentCode,
  ) {
    final func = functionalCode.toUpperCase();
    final doc = documentCode.toUpperCase();
    final pc = p.currency.toUpperCase();
    if (pc == func) return p.price;
    if (pc == doc) {
      if (func == doc) return p.price;
      if (_fxPair != null) {
        final rate = _fxPair!.rate.rateQuotePerBase;
        return _fxPair!.inverted
            ? MoneyStringMath.multiply(p.price, rate)
            : MoneyStringMath.divide(p.price, rate, fractionDigits: 2);
      }
    }
    return null;
  }

  String _gramsFromQuantity(String qty) {
    final q = PosCartQuantity.parse(qty);
    if (q <= 0) return '0';
    final grams = q * 1000;
    return grams.toStringAsFixed(1);
  }

  /// Alta/edición por peso. Si [existing] está presente, congela precios del
  /// ticket (no toma precio nuevo del catálogo aunque [product] exista).
  Future<void> _openWeightedAddSheet({
    CatalogProduct? product,
    PosCartLine? existing,
  }) async {
    final productId = product?.id ?? existing?.productId;
    if (productId == null) return;
    final name = existing?.name ?? product?.name ?? '';
    final sku = existing?.sku ?? product?.sku ?? '';
    final catalogPrice =
        existing?.catalogUnitPrice ?? product?.price;
    final catalogCurrency =
        existing?.catalogCurrency ?? product?.currency;
    if (catalogPrice == null || catalogCurrency == null) return;

    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) return;
    final func = s.functionalCurrency.code;
    final docPrice = PosSalePricing.documentUnitPrice(
      catalogPrice: catalogPrice,
      catalogCurrency: catalogCurrency,
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      pair: _fxPair,
    );
    String? funcPrice = existing?.pricePerKgFunctional;
    if (funcPrice == null || PosCartQuantity.parse(funcPrice) <= 0) {
      if (product != null) {
        funcPrice = _tryPerKgFunctionalPrice(product, func, doc);
      } else {
        // Snapshot de línea: convertir precio catálogo congelado → funcional.
        final pc = catalogCurrency.toUpperCase();
        final f = func.toUpperCase();
        final d = doc.toUpperCase();
        if (pc == f) {
          funcPrice = catalogPrice;
        } else if (pc == d && f == d) {
          funcPrice = catalogPrice;
        } else {
          funcPrice = PosSalePricing.documentUnitPrice(
            catalogPrice: catalogPrice,
            catalogCurrency: catalogCurrency,
            documentCurrencyCode: func,
            functionalCurrencyCode: func,
            pair: _fxPair,
          );
        }
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
    final outcome = await showPosWeightedAddSheet(
      context,
      productName: name,
      functionalCode: func,
      documentCode: doc,
      pricePerKgFunctional: funcPrice,
      pricePerKgDocument: docPrice,
      fxRateDocumentPerFunctional: fxDocPerFunc,
      initialGrams:
          existing?.displayGrams ??
          _gramsFromQuantity(existing?.quantity ?? '0'),
      allowRemoveFromCart: existing != null,
    );
    if (!mounted || outcome == null) return;
    if (outcome is PosWeightedSheetRemoved) {
      _invalidateCheckoutIdempotency();
      setState(() {
        _cart.removeWhere((l) => l.productId == productId);
      });
      _schedulePersistActiveCartDraft();
      _search.clear();
      _searchFocus.unfocus();
      _showCartFeedback('$name quitado del ticket');
      return;
    }
    final res = (outcome as PosWeightedSheetAdded).result;
    _invalidateCheckoutIdempotency();
    final i = _cart.indexWhere((l) => l.productId == productId);
    setState(() {
      final line = PosCartLine(
        productId: productId,
        name: name,
        sku: sku,
        catalogUnitPrice: catalogPrice,
        catalogCurrency: catalogCurrency,
        documentUnitPrice: docPrice,
        documentCurrencyCode: doc,
        quantity: PosCartQuantity.normalizeWeightKg(res.quantityKg),
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
    _schedulePersistActiveCartDraft();
    _search.clear();
    _searchFocus.unfocus();
    _showCartFeedback('$name · ${res.displayGrams} g en el ticket');
  }

  Future<void> _openCashAdvanceSheet({
    CatalogProduct? product,
    PosCartLine? existing,
  }) async {
    final productId = product?.id ?? existing?.productId;
    if (productId == null) return;
    final name = existing?.name ?? product?.name ?? 'Avance';
    final sku = existing?.sku ?? product?.sku ?? '';
    final doc = _selectedDocumentCurrency;
    if (doc == null) {
      _showCheckoutPanelMessage(
        _contextError ?? 'No se cargó la configuración de la tienda.',
        error: true,
      );
      return;
    }
    final outcome = await showPosCashAdvanceSheet(
      context,
      productName: name,
      documentCode: doc,
      initialAdvanceBase: existing?.advanceBaseDocument,
      allowRemoveFromCart: existing != null,
    );
    if (!mounted || outcome == null) return;
    if (outcome is PosCashAdvanceSheetRemoved) {
      _invalidateCheckoutIdempotency();
      setState(() {
        _cart.removeWhere((l) => l.productId == productId);
      });
      _schedulePersistActiveCartDraft();
      _search.clear();
      _searchFocus.unfocus();
      _showCartFeedback('$name quitado del ticket');
      return;
    }
    final res = (outcome as PosCashAdvanceSheetConfirmed).result;
    _invalidateCheckoutIdempotency();
    final i = _cart.indexWhere((l) => l.productId == productId);
    setState(() {
      final line = PosCartLine(
        productId: productId,
        name: name,
        sku: sku,
        catalogUnitPrice: res.totalChargeDocument,
        catalogCurrency: doc,
        documentUnitPrice: res.totalChargeDocument,
        documentCurrencyCode: doc,
        quantity: '1',
        isCashAdvance: true,
        advanceBaseDocument: res.advanceBaseDocument,
      );
      if (i >= 0) {
        _cart[i] = line;
      } else {
        _cart.add(line);
      }
    });
    _schedulePersistActiveCartDraft();
    _search.clear();
    _searchFocus.unfocus();
    _showCartFeedback(
      '$name: ${res.advanceBaseDocument} + comisión ${res.feeDocument} = '
      '${res.totalChargeDocument} $doc',
    );
  }

  Future<void> _addProductToCart(
    CatalogProduct p, {
    String addQty = '1',
  }) async {
    if (!p.active) {
      _showCheckoutPanelMessage(
        'Producto desactivado: no se puede agregar al ticket.',
        error: true,
      );
      return;
    }
    if (PosCashAdvance.isAdvanceProduct(p)) {
      final existingIdx = _cart.indexWhere((l) => l.productId == p.id);
      await _openCashAdvanceSheet(
        product: p,
        existing: existingIdx >= 0 ? _cart[existingIdx] : null,
      );
      return;
    }
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
      await _openWeightedAddSheet(product: p);
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
    _schedulePersistActiveCartDraft();
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

  CatalogProduct? _catalogProductById(String productId) {
    for (final p in _all) {
      if (p.id == productId) return p;
    }
    return null;
  }

  /// Costo unitario funcional congelado al cobrar (`Product.cost` del cache local).
  bool _resolveFrozenUnitCostsForCheckout(Map<String, String> out) {
    final doc = _selectedDocumentCurrency;
    if (doc == null) return false;
    final func = _functionalCode;
    for (final l in _cart) {
      if (l.isCashAdvance) {
        out[l.productId] = '0.00';
        continue;
      }
      final p = _catalogProductById(l.productId);
      if (p == null) {
        _showCheckoutPanelMessage(
          'No se encontró "${l.name}" en el catálogo local. Sincronizá antes de cobrar.',
          error: true,
        );
        return false;
      }
      final cost = catalogUnitCostFunctional(
        catalogCost: p.cost,
        catalogCurrency: p.currency,
        functionalCurrencyCode: func,
        documentCurrencyCode: doc,
        pair: _fxPair,
      );
      if (cost == null) {
        _showCheckoutPanelMessage(
          'No se pudo convertir el costo de "${l.name}" a $func. '
          'Revisá la moneda del producto o la tasa del día.',
          error: true,
        );
        return false;
      }
      out[l.productId] = cost;
    }
    return true;
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
    if (_appliedPayments.isEmpty) {
      if (_activePaymentMethods.isEmpty) {
        _showCheckoutPanelMessage(
          'No hay métodos de pago activos. Sincronizá o configurá métodos en el servidor.',
          error: true,
        );
        return;
      }
      await _openPaymentSheet();
      if (!mounted) return;
      if (_appliedPayments.isEmpty) return;
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

    final stockOk = await _guardStockPoliciesBeforeCheckout();
    if (!stockOk || !mounted) return;

    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;

    _pendingSaleId ??= ClientMutationId.newId();
    final unitCostFunctionalByProductId = <String, String>{};
    if (!_resolveFrozenUnitCostsForCheckout(unitCostFunctionalByProductId)) {
      return;
    }
    final clientSoldAt = DateTime.now().toUtc().toIso8601String();
    final payments = _buildPaymentsForPayload(
      functionalCode: func,
      documentCode: doc,
      saleFxSnapshot: _currentSaleFxSnapshot(
        functionalCode: func,
        documentCode: doc,
      ),
    );
    if (payments == null || payments.isEmpty) {
      _showCheckoutPanelMessage(
        'Seleccioná un método de pago antes de cobrar.',
        error: true,
      );
      return;
    }
    final restBody = SaleCheckoutPayload.build(
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      lines: List<PosCartLine>.from(_cart),
      fxPair: _fxPair,
      deviceId: _terminal!.deviceId,
      appVersion: _terminal!.appVersion,
      payments: payments,
      clientSaleId: _pendingSaleId,
      clientSoldAt: clientSoldAt,
      unitCostFunctionalByProductId: unitCostFunctionalByProductId,
      stockConflictDetected: _checkoutStockConflict ? true : null,
      inventoryValidationMode: _checkoutStockConflict
          ? 'LOCAL_ESTIMATED'
          : 'LOCAL_OK',
      saleOrigin: 'POS',
    );

    // Un solo camino: confirmar en dispositivo → cola. La API no autoriza el cobro.
    await _confirmSaleLocally(restBody, doc);
  }

  /// Persiste venta + cola, baja stock estimado, vacía ticket y sync silencioso.
  Future<void> _confirmSaleLocally(
    Map<String, dynamic> restBody,
    String doc,
  ) async {
    final totalDoc = _cartTotalDocument;
    final clientSaleId = _pendingSaleId;
    final heldId = _activeHeldTicketId;
    final soldByProduct = <String, double>{};
    for (final l in _cart) {
      soldByProduct[l.productId] =
          (soldByProduct[l.productId] ?? 0) + PosCartQuantity.parse(l.quantity);
    }

    await _persistQueuedSaleNoCartClear(
      restBody: restBody,
      doc: doc,
      clientSaleId: clientSaleId,
      totalDocument: totalDoc,
      totalFunctional: _cartTotalFunctional,
      functionalCurrencyCode: _functionalCode,
    );
    await widget.localPrefs.applyLocalInventoryDecrements(
      storeId: widget.storeId,
      soldByProductId: soldByProduct,
    );
    unawaited(_refreshInventoryCacheSilent());

    // Apertura es pantalla explícita (Fase 2); no abrir con fondo 0 al cobrar.

    if (!mounted) return;
    setState(() {
      _cart.clear();
      _pendingSaleId = null;
      _checkoutBusy = false;
      _activeHeldTicketId = null;
    });
    _clearMixedPaymentInputs();
    await _clearActiveCartDraftNow();
    if (heldId != null) {
      await widget.localPrefs.deleteHeldTicket(heldId);
      await _refreshHeldCount();
    }
    await _refreshPendingCount();
    if (!mounted) return;

    _showCheckoutPanelMessage(
      'Venta registrada. Pendiente de enviar con Sincronizar o Cerrar caja.',
      error: false,
      duration: const Duration(seconds: 3),
    );

    // Cola local: no flush automático. Sale con Sincronizar o Cerrar caja.
  }

  PosCartLine _cloneCartLine(PosCartLine l) {
    return PosCartLine(
      productId: l.productId,
      name: l.name,
      sku: l.sku,
      catalogUnitPrice: l.catalogUnitPrice,
      catalogCurrency: l.catalogCurrency,
      documentUnitPrice: l.documentUnitPrice,
      documentCurrencyCode: l.documentCurrencyCode,
      quantity: l.quantity,
      isByWeight: l.isByWeight,
      displayGrams: l.displayGrams,
      pricePerKgFunctional: l.pricePerKgFunctional,
      lineAmountFunctional: l.lineAmountFunctional,
      lineAmountDocument: l.lineAmountDocument,
      isCashAdvance: l.isCashAdvance,
      advanceBaseDocument: l.advanceBaseDocument,
    );
  }

  /// Encola venta y ticket local sin tocar el carrito.
  /// Reutiliza el mismo `opId` si ya hay cola para este `sale.id` (evita doble factura).
  Future<void> _persistQueuedSaleNoCartClear({
    required Map<String, dynamic> restBody,
    required String doc,
    required String? clientSaleId,
    required String? totalDocument,
    String? totalFunctional,
    String? functionalCurrencyCode,
  }) async {
    final saleMap = SaleCheckoutPayload.syncSaleFromRestBody(
      restBody,
      widget.storeId,
      fxSource: 'POS_OFFLINE',
    );
    final saleId =
        (clientSaleId ?? saleMap['id']?.toString() ?? '').trim();
    final existingOpId = saleId.isEmpty
        ? null
        : await widget.localPrefs.findPendingSaleOpId(
            storeId: widget.storeId,
            saleId: saleId,
          );
    final syncOpId = existingOpId ?? ClientMutationId.newId();
    await widget.localPrefs.appendPendingSale(
      PendingSaleEntry(
        opId: syncOpId,
        storeId: widget.storeId,
        sale: saleMap,
        opTimestampIso: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    if (saleId.isNotEmpty && totalDocument != null) {
      final ticketNo = await widget.localPrefs.allocateLocalTicketDisplayCode();
      var tf = totalFunctional?.trim();
      var fc = functionalCurrencyCode?.trim();
      if (tf == null || tf.isEmpty) {
        final fromPayload =
            RecentSaleFunctionalEnricher.functionalFromSalePayload(
              sale: saleMap,
              totalDocument: totalDocument,
            );
        if (fromPayload != null) {
          tf = fromPayload.$1;
          fc = fromPayload.$2;
        }
      }
      await widget.localPrefs.prependRecentSaleTicket(
        RecentSaleTicket(
          storeId: widget.storeId,
          saleId: saleId,
          totalDocument: totalDocument,
          documentCurrencyCode: doc,
          recordedAtIso: DateTime.now().toIso8601String(),
          status: RecentSaleTicket.statusQueued,
          displayCode: ticketNo,
          totalFunctional: tf,
          functionalCurrencyCode: fc,
        ),
      );
    }
    if (mounted) await _refreshPendingCount();
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

  double get _paymentFunctionalAmount =>
      _appliedPayments.fold(0.0, (a, p) => a + p.amountFunctional);

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
    if (!_hasAnyMixedPaymentInput) return false;
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

  String? get _mixedPaymentDetailLine {
    if (!_hasAnyMixedPaymentInput) return null;
    final doc = _selectedDocumentCurrency ?? '';
    final remDoc = _cartTotalDocumentAmount - _paymentTotalInDocument;
    final remDocClamped = remDoc < 0 ? 0.0 : remDoc;
    final methods = _appliedPayments
        .map((p) => '${p.methodName}: ${_fmt2(p.amountFunctional)}')
        .join(' · ');
    return '$methods · resta $doc: ${_fmt2(remDocClamped)}';
  }

  double get _mixedChangeFunctional {
    final change = _paymentFunctionalAmount - _cartTotalFunctionalAmount;
    return change > 0 ? change : 0;
  }

  Future<void> _openPaymentSheet() async {
    final func = _functionalCode;
    if (func.isEmpty) return;
    final remaining = max(
      0.0,
      _cartTotalFunctionalAmount - _paymentFunctionalAmount,
    );
    final added = await showPosPaymentSheet(
      context,
      methods: _activePaymentMethods,
      functionalCode: func,
      remainingFunctional: remaining,
    );
    if (!mounted || added == null) return;
    setState(() => _appliedPayments.add(added));
    _showCheckoutPanelMessage(
      'Pago ${added.methodName}: ${_fmt2(added.amountFunctional)} $func. '
      '$_remainingMixedLabel',
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
    final fx = <String, dynamic>{...saleFxSnapshot};
    final totalSale = _cartTotalFunctionalAmount;
    if (totalSale <= 0 || _appliedPayments.isEmpty) return null;

    final lines = List<PosAppliedPayment>.from(_appliedPayments);

    var remaining = totalSale;
    for (final p in lines) {
      if (remaining <= 0) break;
      final applied = min(p.amountFunctional, remaining);
      if (applied <= 0) continue;
      payments.add({
        'method': p.methodCode,
        'amount': _fmt2(applied),
        'currencyCode': functionalCode.toUpperCase(),
        if (functionalCode.toUpperCase() != documentCode.toUpperCase())
          'fxSnapshot': Map<String, dynamic>.from(fx),
      });
      remaining -= applied;
    }
    return payments.isEmpty ? null : payments;
  }

  void _clearMixedPaymentInputs() {
    _paymentFunctionalCtrl.clear();
    _appliedPayments.clear();
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

  Widget _posCartDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: PosSaleUi.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: PosSaleUi.text,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCartLinePriceDetail({
    required PosCartLine line,
    required String unitFunctional,
    required String lineTotalFunctional,
    required String functionalCode,
    required String documentCode,
  }) async {
    if (!mounted) return;
    _ensureSearchUnfocusedForCheckout();
    final docC = documentCode.trim();
    final stockLabel = await _stockLabelFromLocalCache(line.productId);
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: PosSaleUi.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          titlePadding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 16, 12),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  line.name,
                  style: const TextStyle(
                    color: PosSaleUi.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.close,
                  color: PosSaleUi.textMuted,
                  size: 22,
                ),
                onPressed: () => Navigator.pop(ctx),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (line.isCashAdvance &&
                  line.advanceBaseDocument != null) ...[
                _posCartDetailRow(
                  'Monto avance',
                  '${line.advanceBaseDocument} $docC',
                ),
                _posCartDetailRow(
                  'Comisión ${PosCashAdvance.feePercentLabel}',
                  '${PosCashAdvance.feeFromAdvanceAmount(line.advanceBaseDocument!)} $docC',
                ),
                _posCartDetailRow(
                  'Total a cobrar',
                  '${line.documentUnitPrice} $docC',
                ),
              ],
              if (line.isByWeight && line.displayGrams != null)
                _posCartDetailRow('Peso', '${line.displayGrams} g'),
              _posCartDetailRow('Stock disponible', stockLabel),
              _posCartDetailRow('Costo $functionalCode', unitFunctional),
              _posCartDetailRow('Costo $docC', line.documentUnitPrice),
              _posCartDetailRow(
                'Total $functionalCode',
                '$lineTotalFunctional $functionalCode',
              ),
              _posCartDetailRow(
                'Total $docC',
                '${line.lineTotalDocument} $docC',
              ),
              const SizedBox(height: 6),
              Text(
                'SKU ${line.sku}',
                style: const TextStyle(
                  fontSize: 11,
                  color: PosSaleUi.textMuted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Stock desde caché local de inventario (sin llamar al API).
  Future<String> _stockLabelFromLocalCache(String productId) async {
    final pid = productId.trim();
    if (pid.isEmpty) return 'Sin dato local';
    try {
      final inv = await widget.localPrefs.loadInventoryCache(widget.storeId);
      for (final row in inv) {
        final id = row.productId.trim().isNotEmpty
            ? row.productId.trim()
            : (row.product?.id.trim() ?? '');
        if (id != pid) continue;
        final q = row.quantity.trim();
        final r = row.reserved.trim();
        final qty = double.tryParse(q.replaceAll(',', '.'));
        final reserved = double.tryParse(r.replaceAll(',', '.')) ?? 0;
        if (qty == null) return q.isEmpty ? 'Sin dato local' : q;
        final available = qty - reserved;
        final availStr = available == available.roundToDouble()
            ? '${available.round()}'
            : available.toStringAsFixed(2);
        if (reserved > 0) {
          return '$availStr (disp.) · $q en inventario';
        }
        return availStr;
      }
    } catch (_) {}
    return 'Sin dato local';
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
    final q = _search.text.trim();
    if (q.isEmpty) return const [];
    final found = _all.where((p) {
      return searchTextMatchesAnyField(q, [p.name, p.sku, p.barcode]);
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

  /// En móvil, ocultar cobro solo mientras se busca de verdad (texto o teclado).
  /// Si el foco queda “pegado” sin teclado ni texto, el botón Cobrar no debe desaparecer.
  bool _hideCheckoutWhileSearchFocused(BuildContext context) {
    if (!_isCompactPosLayout(context)) return false;
    if (!_searchFocus.hasFocus) return false;
    if (_search.text.trim().isNotEmpty) return true;
    return MediaQuery.viewInsetsOf(context).bottom > 0;
  }

  void _ensureSearchUnfocusedForCheckout() {
    if (!_searchFocus.hasFocus) return;
    _searchFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

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
          primaryLine: PosCashAdvance.isAdvanceProduct(p)
              ? 'Avance + comisión ${PosCashAdvance.feePercentLabel}'
              : (docLbl ?? '${p.price} ${p.currency}'),
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

  bool _lineIsCashAdvance(PosCartLine line) {
    if (line.isCashAdvance) return true;
    final p = _catalogByProductId(line.productId);
    return p != null && PosCashAdvance.isAdvanceProduct(p);
  }

  void _bumpLine(int index, double delta) {
    final line = _cart[index];
    if (_lineIsCashAdvance(line)) {
      unawaited(
        _openCashAdvanceSheet(
          product: _catalogByProductId(line.productId),
          existing: line.isCashAdvance ? line : null,
        ),
      );
      return;
    }
    if (line.isByWeight) {
      // Editar desde snapshot del ticket (sirve si el producto ya no está activo).
      unawaited(
        _openWeightedAddSheet(
          product: _catalogByProductId(line.productId),
          existing: line,
        ),
      );
      return;
    }
    _invalidateCheckoutIdempotency();
    final cur = PosCartQuantity.parse(_cart[index].quantity);
    final next = cur + delta;
    if (next <= 0) {
      setState(() => _cart.removeAt(index));
      _schedulePersistActiveCartDraft();
      return;
    }
    setState(() {
      _cart[index].quantity = PosCartQuantity.stringify(next);
    });
    _schedulePersistActiveCartDraft();
  }

  Future<void> _onLineQtyTap(int index) async {
    final line = _cart[index];
    if (_lineIsCashAdvance(line)) {
      await _openCashAdvanceSheet(
        product: _catalogByProductId(line.productId),
        existing: line.isCashAdvance ? line : null,
      );
      return;
    }
    if (line.isByWeight) {
      await _openWeightedAddSheet(
        product: _catalogByProductId(line.productId),
        existing: line,
      );
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
    _schedulePersistActiveCartDraft();
  }

  void _removeLineByProductId(String productId) {
    setState(() {
      _invalidateCheckoutIdempotency();
      _cart.removeWhere((l) => l.productId == productId);
    });
    _schedulePersistActiveCartDraft();
  }

  void _clearCart() {
    if (_cart.isEmpty) return;
    setState(() {
      _invalidateCheckoutIdempotency();
      _cart.clear();
      _activeHeldTicketId = null;
    });
    _clearMixedPaymentInputs();
    unawaited(_clearActiveCartDraftNow());
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _pendingQueueServerAvailableHint
                              ? Icons.wifi_find
                              : Icons.cloud_upload_outlined,
                          color: PosSaleUi.primary,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        if (_pendingQueueServerAvailableHint)
                          Expanded(
                            child: Text(
                              'Online: desactivá offline en Inicio ($_pendingSyncCount)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: PosSaleUi.text,
                                fontSize: 10,
                              ),
                            ),
                          )
                        else
                          Text(
                            '$_pendingSyncCount',
                            style: const TextStyle(
                              color: PosSaleUi.text,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        TextButton(
                          onPressed: _flushBusy
                              ? null
                              : () =>
                                    _runSyncCycle(silent: false, doPull: true),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            minimumSize: const Size(0, 26),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: _flushBusy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: PosSaleUi.primary,
                                  ),
                                )
                              : const Text(
                                  'Sincronizar',
                                  style: TextStyle(fontSize: 11),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              PosSaleTopBar(
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
                                                  child: NotificationListener<
                                                    ScrollNotification
                                                  >(
                                                    onNotification: (n) {
                                                      if (n
                                                          is ScrollStartNotification) {
                                                        _ensureSearchUnfocusedForCheckout();
                                                      }
                                                      return false;
                                                    },
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
                                                      final dCode =
                                                          doc ??
                                                          l.documentCurrencyCode;
                                                      InventoryLine? inv;
                                                      for (final e
                                                          in _inventoryCache) {
                                                        if (e.productId ==
                                                            l.productId) {
                                                          inv = e;
                                                          break;
                                                        }
                                                      }
                                                      CatalogProduct? prod;
                                                      for (final p in _all) {
                                                        if (p.id ==
                                                            l.productId) {
                                                          prod = p;
                                                          break;
                                                        }
                                                      }
                                                      final lineAssessment =
                                                          assessPosCartStock(
                                                            cart: [l],
                                                            catalog: prod == null
                                                                ? const []
                                                                : [prod],
                                                            inventory:
                                                                inv == null
                                                                ? const []
                                                                : [inv],
                                                            settings: _settings,
                                                            catalogLikelyFresh:
                                                                _catalogLikelyFresh,
                                                          );
                                                      final st =
                                                          lineAssessment
                                                              .lines
                                                              .isEmpty
                                                          ? null
                                                          : lineAssessment
                                                                .lines
                                                                .first;
                                                      final advanceLabel =
                                                          l.isCashAdvance &&
                                                              l.advanceBaseDocument !=
                                                                  null
                                                          ? 'Avance ${l.advanceBaseDocument} $dCode'
                                                          : null;
                                                      final feeLabel =
                                                          l.isCashAdvance &&
                                                              l.advanceBaseDocument !=
                                                                  null
                                                          ? 'comisión ${PosCashAdvance.feeFromAdvanceAmount(l.advanceBaseDocument!)}'
                                                          : null;
                                                      return PosSaleCartLineTile(
                                                        line: l,
                                                        imageUrl:
                                                            _cartImageUrlForProductId(
                                                              l.productId,
                                                            ),
                                                        unitFunctional: uf,
                                                        lineTotalFunctional: lf,
                                                        functionalCode: func,
                                                        documentCode: dCode,
                                                        stockStatusLabel:
                                                            advanceLabel ??
                                                            st?.status.labelEs,
                                                        stockQtyLabel:
                                                            feeLabel ??
                                                            (st?.availableQty ==
                                                                    null
                                                                ? null
                                                                : 'qty ${st!.availableLabel}'),
                                                        onMinus: () {
                                                          _ensureSearchUnfocusedForCheckout();
                                                          _bumpLine(i, -1);
                                                        },
                                                        onPlus: () {
                                                          _ensureSearchUnfocusedForCheckout();
                                                          _bumpLine(i, 1);
                                                        },
                                                        onQtyTap: () {
                                                          _ensureSearchUnfocusedForCheckout();
                                                          _onLineQtyTap(i);
                                                        },
                                                        onDismissed: () =>
                                                            _removeLineByProductId(
                                                              l.productId,
                                                            ),
                                                        onShowPriceDetail: () {
                                                          unawaited(
                                                            _showCartLinePriceDetail(
                                                              line: l,
                                                              unitFunctional:
                                                                  uf,
                                                              lineTotalFunctional:
                                                                  lf,
                                                              functionalCode:
                                                                  func,
                                                              documentCode:
                                                                  dCode,
                                                            ),
                                                          );
                                                        },
                                                      );
                                                    },
                                                  ),
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
                  onOpenMixedPayment: _openPaymentSheet,
                  onClearMixedPayment: _appliedPayments.isNotEmpty
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
