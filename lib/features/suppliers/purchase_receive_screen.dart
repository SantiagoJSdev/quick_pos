import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/purchases_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/pos/post_purchase_price_hint.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/supplier.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/network/network_errors.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/pos/purchase_unit_cost_convert.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_purchase_receive_entry.dart';
import '../../core/sync/purchase_receive_payload.dart';
import '../../core/sync/sync_cycle.dart';
import '../../core/text/search_text_match.dart';
import '../shell/shell_online_scope.dart';
import 'supplier_form_screen.dart';

final _decimalPositive = RegExp(r'^\d+(\.\d+)?$');
final _decimalNonNegative = RegExp(r'^\d+(\.\d+)?$');

String _mergeQuantityStrings(String a, String b) {
  final sum = double.parse(a.replaceAll(',', '.')) +
      double.parse(b.replaceAll(',', '.'));
  if (sum == sum.roundToDouble()) return sum.round().toString();
  return sum.toString();
}

String _normalizePurchaseUnitCost(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  return t.isEmpty ? '0' : t;
}

bool _isZeroUnitCost(String unitCost) {
  final v = double.tryParse(unitCost.replaceAll(',', '.'));
  return v != null && v == 0;
}

/// Línea agregada a la recepción (varios productos por documento).
class _PurchaseLineDraft {
  _PurchaseLineDraft({
    required this.lineKey,
    required this.product,
    required this.quantity,
    required this.unitCost,
  });

  final String lineKey;
  final CatalogProduct product;
  final String quantity;
  final String unitCost;
}

/// Recepción de mercancía: `POST /purchases` o cola `PURCHASE_RECEIVE` si no hay red.
class PurchaseReceiveScreen extends StatefulWidget {
  const PurchaseReceiveScreen({
    super.key,
    required this.storeId,
    required this.localPrefs,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.productsApi,
    required this.purchasesApi,
    required this.suppliersApi,
    required this.syncApi,
    required this.catalogInvalidationBus,
  });

  final String storeId;
  final LocalPrefs localPrefs;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final ProductsApi productsApi;
  final PurchasesApi purchasesApi;
  final SuppliersApi suppliersApi;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;

  @override
  State<PurchaseReceiveScreen> createState() => _PurchaseReceiveScreenState();
}

class _PurchaseReceiveScreenState extends State<PurchaseReceiveScreen> {
  List<Supplier> _suppliers = [];
  List<CatalogProduct> _products = [];
  BusinessSettings? _settings;
  String? _contextError;
  Supplier? _selectedSupplier;
  CatalogProduct? _selectedProduct;

  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _productField = TextEditingController();
  final _productFocus = FocusNode();
  final _invoiceRef = TextEditingController();
  final _purchaseNotes = TextEditingController();
  final _initialPaid = TextEditingController();
  final List<_PurchaseLineDraft> _lines = [];
  bool _loading = true;
  bool _submitting = false;
  String? _formError;

  /// PAID | CREDIT | PARTIAL
  String _paymentStatus = 'PAID';
  DateTime? _dueDate;

  String? _purchaseClientId;
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
    unawaited(_load());
  }

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _productField.dispose();
    _productFocus.dispose();
    _invoiceRef.dispose();
    _purchaseNotes.dispose();
    _initialPaid.dispose();
    super.dispose();
  }

  Future<List<Supplier>> _loadAllSuppliers() async {
    final all = <Supplier>[];
    String? cursor;
    for (var i = 0; i < 40; i++) {
      final page = await widget.suppliersApi.listSuppliers(
        widget.storeId,
        cursor: cursor,
        limit: 200,
        active: 'all',
      );
      all.addAll(page.items);
      final next = page.nextCursor?.trim();
      if (next == null || next.isEmpty) break;
      cursor = next;
    }
    all.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return all;
  }

  String _supplierDisplay(Supplier s) {
    final t = s.taxId?.trim();
    if (t != null && t.isNotEmpty) return '${s.name} · $t';
    return s.name;
  }

  /// Asegura que [_selectedSupplier] apunte a una instancia de [_suppliers] (misma id).
  void _reconcileSupplierDropdown() {
    if (_suppliers.isEmpty) {
      _selectedSupplier = null;
      return;
    }
    final id = _selectedSupplier?.id.trim() ?? '';
    if (id.isNotEmpty) {
      for (final s in _suppliers) {
        if (s.id == id) {
          _selectedSupplier = s;
          return;
        }
      }
    }
    _selectedSupplier = _suppliers.first;
  }

  String _productDisplay(CatalogProduct p) {
    final bc = p.barcode?.trim();
    if (bc != null && bc.isNotEmpty) {
      return '${p.name} · ${p.sku} · $bc';
    }
    return '${p.name} · ${p.sku}';
  }

  String _catalogCostSummary(CatalogProduct p) {
    final cost = p.cost.trim();
    if (cost.isEmpty || cost == '0' || cost == '0.0' || cost == '0.00') {
      return 'sin costo en catálogo';
    }
    final cur = p.currency.trim();
    final doc = _purchaseDocumentCurrency?.trim() ?? '';
    if (doc.isNotEmpty && cur.toUpperCase() == doc.toUpperCase()) {
      return '$cost $cur';
    }
    return '$cost $cur (factura en $doc)';
  }

  String _productAutocompleteSubtitle(CatalogProduct p) {
    final sku = p.sku.trim();
    final bc = p.barcode?.trim();
    final parts = <String>[
      if (sku.isNotEmpty) sku,
      if (bc != null && bc.isNotEmpty) bc,
      'cat. ${_catalogCostSummary(p)}',
    ];
    return parts.join(' · ');
  }

  void _applyProductSelection(CatalogProduct p) {
    setState(() {
      _selectedProduct = p;
      _productField.text = _productDisplay(p);
      final doc = _purchaseDocumentCurrency?.trim().toUpperCase() ?? '';
      final pc = p.currency.trim().toUpperCase();
      final cost = p.cost.trim();
      if (cost.isNotEmpty &&
          pc == doc &&
          (double.tryParse(cost.replaceAll(',', '.')) ?? 0) > 0) {
        _unitCost.text = cost;
      }
    });
  }

  CatalogProduct? get _productForCostHint =>
      _selectedProduct ?? _effectiveProduct();

  String? get _unitCostHelperText {
    final p = _productForCostHint;
    if (p == null) return null;
    return 'Catálogo hoy: ${_catalogCostSummary(p)}';
  }

  /// Hay datos del usuario que no deben borrarse si [_load] vuelve a correr
  /// (p. ej. shell offline→online): si solo queda factura/notas y el producto se
  /// limpia, «Agregar línea» deja de funcionar hasta re-elegir producto.
  bool get _preserveReceiptDraft =>
      _lines.isNotEmpty ||
      _invoiceRef.text.trim().isNotEmpty ||
      _purchaseNotes.text.trim().isNotEmpty ||
      _productField.text.trim().isNotEmpty ||
      _quantity.text.trim().isNotEmpty ||
      _unitCost.text.trim().isNotEmpty ||
      _selectedProduct != null;

  void _reconcileSelectedProductAfterCatalogReload() {
    final id = _selectedProduct?.id.trim() ?? '';
    if (id.isEmpty) return;
    for (final p in _products) {
      if (p.id == id) {
        _selectedProduct = p;
        _productField.text = _productDisplay(p);
        return;
      }
    }
    _selectedProduct = null;
  }

  /// Texto = último seleccionado, o filtro con una sola coincidencia; si no, null.
  CatalogProduct? _effectiveProduct() {
    if (_products.isEmpty) return null;
    final raw = _productField.text.trim();
    if (raw.isEmpty) return null;
    final textLower = raw.toLowerCase();
    if (_selectedProduct != null &&
        _productDisplay(_selectedProduct!).toLowerCase() == textLower) {
      return _selectedProduct;
    }
    final filtered = _products.where((p) {
      final n = p.name.toLowerCase();
      final s = p.sku.toLowerCase();
      final b = (p.barcode ?? '').toLowerCase();
      return n.contains(textLower) ||
          s.contains(textLower) ||
          b.contains(textLower);
    }).toList();
    if (filtered.length == 1) return filtered.first;
    return null;
  }

  /// Compras: solo moneda funcional (USD operativo).
  String? get _purchaseDocumentCurrency {
    final func = _functionalCode.trim();
    return func.isEmpty ? null : func;
  }

  String get _functionalCode => _settings?.functionalCurrency.code ?? '';

  Future<void> _bootstrapOfflineLoad() async {
    final cachedCatalog = await widget.localPrefs.loadCatalogProductsCache();
    final active = cachedCatalog.where((p) => p.active).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final local = await widget.localPrefs.getLocalSuppliers();
    final mapped =
        local
            .map(
              (x) => Supplier(
                id: x.id,
                storeId: widget.storeId,
                name: x.name,
                active: true,
              ),
            )
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final cached = await widget.localPrefs.loadBusinessSettingsCache(
      widget.storeId,
    );
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _suppliers = mapped;
        _settings = cached;
        _products = active;
        _contextError = null;
        _reconcileSupplierDropdown();
        if (!_preserveReceiptDraft) {
          _selectedProduct = null;
          _productField.text = '';
        } else {
          _reconcileSelectedProductAfterCatalogReload();
        }
      });
    } else {
      setState(() {
        _products = active;
        _suppliers = mapped;
        _settings = null;
        _contextError =
            'Sin configuración en caché. Conectate para cargar la tienda.';
        _selectedSupplier = null;
        if (!_preserveReceiptDraft) {
          _selectedProduct = null;
          _productField.text = '';
        } else {
          _reconcileSelectedProductAfterCatalogReload();
        }
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _contextError = null;
    });
    if (!_shellOnline) {
      await _bootstrapOfflineLoad();
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final settings = await widget.storesApi.getBusinessSettings(
        widget.storeId,
      );
      final products = await widget.productsApi.listProducts(
        widget.storeId,
        includeInactive: false,
      );
      final suppliers = await _loadAllSuppliers();
      final active = products.where((p) => p.active).toList(growable: false);
      active.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _settings = settings;
        _products = active;
        _reconcileSupplierDropdown();
        if (!_preserveReceiptDraft) {
          _selectedProduct = null;
          _productField.text = '';
        } else {
          _reconcileSelectedProductAfterCatalogReload();
        }
      });
      if (mounted) setState(() => _loading = false);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _contextError = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _contextError = e.toString();
      });
    }
  }

  void _addLineToReceipt() {
    setState(() => _formError = null);
    if (_productField.text.trim().isEmpty) {
      setState(() => _formError = 'Elegí un producto para agregar.');
      return;
    }
    final prod = _effectiveProduct();
    if (prod == null) {
      setState(() {
        _formError =
            'Producto no identificado: tocá una opción de la lista o '
            'dejá una sola coincidencia al filtrar.';
      });
      return;
    }
    setState(() => _selectedProduct = prod);
    final qty = _quantity.text.trim();
    final costNorm = _normalizePurchaseUnitCost(_unitCost.text);
    if (!_decimalPositive.hasMatch(qty)) {
      setState(() => _formError = 'Cantidad: número decimal > 0.');
      return;
    }
    final qtyVal = double.tryParse(qty);
    if (qtyVal == null || qtyVal <= 0) {
      setState(() => _formError = 'Cantidad debe ser mayor que 0.');
      return;
    }
    if (!_decimalNonNegative.hasMatch(costNorm)) {
      setState(
        () => _formError = 'Costo unitario (moneda documento): decimal válido ≥ 0.',
      );
      return;
    }
    final costVal = double.tryParse(costNorm);
    if (costVal == null || costVal < 0) {
      setState(() => _formError = 'Costo unitario inválido.');
      return;
    }

    final existingIdx = _lines.indexWhere((e) => e.product.id == prod.id);
    if (existingIdx >= 0) {
      final existing = _lines[existingIdx];
      if (existing.unitCost != costNorm) {
        setState(
          () => _formError =
              '«${prod.name}» ya está en la factura con costo ${existing.unitCost}. '
              'Quitá esa línea o usá el mismo costo para sumar cantidad.',
        );
        return;
      }
      setState(() {
        _lines[existingIdx] = _PurchaseLineDraft(
          lineKey: existing.lineKey,
          product: prod,
          quantity: _mergeQuantityStrings(existing.quantity, qty),
          unitCost: costNorm,
        );
        _selectedProduct = null;
        _productField.clear();
        _quantity.clear();
        _unitCost.clear();
      });
      return;
    }

    setState(() {
      _lines.add(
        _PurchaseLineDraft(
          lineKey: ClientMutationId.newId(),
          product: prod,
          quantity: qty,
          unitCost: costNorm,
        ),
      );
      _selectedProduct = null;
      _productField.clear();
      _quantity.clear();
      _unitCost.clear();
    });
  }

  void _removeLineByKey(String lineKey) {
    setState(() => _lines.removeWhere((e) => e.lineKey == lineKey));
  }

  /// Alinea `Product.cost` con el costo unitario **real** de esta recepción (no el promedio de stock).
  Future<List<String>> _applyCatalogCostFromPurchaseLines({
    required String documentCode,
    required String functionalCode,
  }) async {
    final failures = <String>[];
    final refreshedProducts = <CatalogProduct>[];
    for (final draft in _lines) {
      if (_isZeroUnitCost(draft.unitCost)) continue;
      final p = draft.product;
      final costStr = purchaseUnitCostInProductCurrency(
        unitCostDocument: draft.unitCost,
        documentCurrencyCode: documentCode,
        functionalCurrencyCode: functionalCode,
        fxPair: null,
        productCurrencyCode: p.currency,
      );
      if (costStr == null) {
        failures.add('${p.name} (${p.currency} ≠ documento/funcional)');
        continue;
      }
      try {
        final updated = await widget.productsApi.updateProduct(
          widget.storeId,
          p.id,
          {
            'cost': costStr,
            'applySuggestedListPrice': true,
          },
        );
        refreshedProducts.add(updated);
      } on ApiError catch (e) {
        debugPrint('[Purchase] PATCH cost ${p.id}: ${e.userMessageForSupport}');
        failures.add(p.name);
      } catch (e) {
        debugPrint('[Purchase] PATCH cost ${p.id}: $e');
        failures.add(p.name);
      }
    }
    if (refreshedProducts.isNotEmpty) {
      await widget.localPrefs.upsertCatalogProductsInCache(refreshedProducts);
    }
    return failures;
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    final s = _settings;
    final doc = _purchaseDocumentCurrency;
    if (s == null || doc == null) {
      setState(() => _formError = 'Configuración de tienda no disponible.');
      return;
    }
    final sup = _selectedSupplier;
    if (sup == null) {
      setState(() => _formError = 'Elegí un proveedor en el desplegable.');
      return;
    }
    if (_lines.isEmpty) {
      setState(
        () => _formError =
            'Agregá al menos una línea (producto, cantidad y costo).',
      );
      return;
    }
    final productIds = _lines.map((e) => e.product.id).toList();
    if (productIds.toSet().length != productIds.length) {
      setState(
        () => _formError =
            'Hay productos duplicados en la factura. Dejá una línea por producto.',
      );
      return;
    }
    final func = s.functionalCurrency.code;

    final supplierInvoiceRef =
        PurchaseReceivePayload.buildSupplierInvoiceReferenceForApi(
          invoiceRef: _invoiceRef.text,
          documentNotes: _purchaseNotes.text,
        );
    if (supplierInvoiceRef.length >
        PurchaseReceivePayload.maxSupplierInvoiceReferenceLength) {
      setState(
        () => _formError =
            'Factura + notas: máximo '
            '${PurchaseReceivePayload.maxSupplierInvoiceReferenceLength} '
            'caracteres (límite del servidor).',
      );
      return;
    }

    String? dueDateStr;
    String? initialPaidStr;
    if (_paymentStatus == 'CREDIT' || _paymentStatus == 'PARTIAL') {
      if (_dueDate != null) {
        final d = _dueDate!;
        dueDateStr =
            '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}';
      }
    }
    if (_paymentStatus == 'PARTIAL') {
      final raw = _initialPaid.text.trim();
      if (!_decimalPositive.hasMatch(raw) || double.tryParse(raw) == null) {
        setState(
          () => _formError =
              'En Parcial, indicá el abono inicial en moneda funcional '
              '(número > 0).',
        );
        return;
      }
      final v = double.parse(raw);
      if (v <= 0) {
        setState(() => _formError = 'El abono inicial debe ser mayor que 0.');
        return;
      }
      initialPaidStr = raw;
    }

    _purchaseClientId ??= ClientMutationId.newId();
    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;

    final fxSnap = PurchaseReceivePayload.buildFxSnapshot(
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      fxPair: null,
    );
    final lines = _lines
        .map(
          (e) => PurchaseReceivePayload.line(
            productId: e.product.id,
            quantity: e.quantity,
            unitCost: e.unitCost,
          ),
        )
        .toList();
    final restBody = PurchaseReceivePayload.toRestBody(
      supplierId: sup.id,
      documentCurrencyCode: doc,
      lines: lines,
      fxSnapshot: fxSnap,
      clientPurchaseId: _purchaseClientId,
      supplierInvoiceReference:
          supplierInvoiceRef.isEmpty ? null : supplierInvoiceRef,
      paymentStatus: _paymentStatus,
      dueDate: dueDateStr,
      initialAmountPaidFunctional: initialPaidStr,
    );
    debugPrint(
      '[Purchase] POST /purchases lines=${lines.length} '
      'paymentStatus=$_paymentStatus '
      'supplierInvoiceRefLen=${supplierInvoiceRef.length} '
      'bodyKeys=${restBody.keys.join(",")} '
      'hasSupplierInvoiceReference=${restBody.containsKey("supplierInvoiceReference")}',
    );

    setState(() => _submitting = true);
    try {
      await widget.purchasesApi.createPurchase(widget.storeId, restBody);
      if (!mounted) return;
      final costFailures = await _applyCatalogCostFromPurchaseLines(
        documentCode: doc,
        functionalCode: func,
      );
      if (!mounted) return;
      widget.catalogInvalidationBus.invalidateFromLocalMutation(
        productIds: _lines.map((e) => e.product.id).toSet(),
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
      final String snackText;
      final hasZeroCostLines = _lines.any((e) => _isZeroUnitCost(e.unitCost));
      if (costFailures.isEmpty) {
        snackText =
            '${PostPurchasePriceHint.afterPurchaseWithCatalogCostUpdatedSnackMessage}'
            '${hasZeroCostLines ? '\n\n${PostPurchasePriceHint.zeroCostLineNote}' : ''}';
      } else {
        snackText =
            'Compra registrada.\n\n'
            'Se actualizó el costo en ficha donde fue posible. '
            'No aplica o falló para: ${costFailures.join(", ")}.\n\n'
            'El precio de lista no se modifica solo; revisalo en Catálogo si aplica.'
            '${hasZeroCostLines ? '\n\n${PostPurchasePriceHint.zeroCostLineNote}' : ''}';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: costFailures.isEmpty ? 8 : 12),
          content: Text(snackText),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      var msg = e.purchaseReceiveMessageEs;
      if (e.statusCode == 400) {
        final blob = '${e.error} ${e.messages.join(' ')}'.toLowerCase();
        if (blob.contains('inactive') || blob.contains('inactivo')) {
          msg =
              'El proveedor está dado de baja. Elegí otro activo o reactivalo '
              'en Proveedores (editar y activar).\n$msg';
        }
      }
      setState(() => _formError = msg);
    } catch (e) {
      if (!mounted) return;
      if (isLikelyNetworkFailure(e)) {
        final syncOpId = ClientMutationId.newId();
        final purchaseMap = PurchaseReceivePayload.toSyncPurchaseObject(
          storeId: widget.storeId,
          supplierId: sup.id,
          documentCurrencyCode: doc,
          lines: lines,
          fxSnapshot: fxSnap,
          clientPurchaseId: _purchaseClientId,
          fxSource: 'POS_OFFLINE',
          supplierInvoiceReference:
              supplierInvoiceRef.isEmpty ? null : supplierInvoiceRef,
          paymentStatus: _paymentStatus,
          dueDate: dueDateStr,
          initialAmountPaidFunctional: initialPaidStr,
        );
        await widget.localPrefs.appendPendingPurchaseReceive(
          PendingPurchaseReceiveEntry(
            opId: syncOpId,
            storeId: widget.storeId,
            purchase: purchaseMap,
            opTimestampIso: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        if (!mounted) return;
        widget.catalogInvalidationBus.invalidateFromLocalMutation(
          productIds: _lines.map((e) => e.product.id).toSet(),
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
              'Sin conexión: compra en cola. Se enviará con sync/push al recuperar red.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _formError = e.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva factura')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contextError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_contextError!),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_suppliers.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'No hay proveedores cargados para esta tienda. '
                            'Creá uno desde Proveedores o con el botón de abajo.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.tonal(
                            onPressed: () async {
                              final ok = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (ctx) => SupplierFormScreen(
                                    storeId: widget.storeId,
                                    suppliersApi: widget.suppliersApi,
                                    localPrefs: widget.localPrefs,
                                    shellOnline: _shellOnline,
                                  ),
                                ),
                              );
                              if (ok == true && mounted) await _load();
                            },
                            child: const Text('Nuevo proveedor'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Text(
                    'Proveedor (todos en esta tienda)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<Supplier>(
                    isExpanded: true,
                    value: _selectedSupplier,
                    hint: const Text('Elegí proveedor'),
                    items: _suppliers
                        .map(
                          (s) => DropdownMenuItem<Supplier>(
                            value: s,
                            child: Text(
                              '${_supplierDisplay(s)}${s.active ? '' : ' (inactivo)'}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (s) => setState(() => _selectedSupplier = s),
                  ),
                ],
                if (_suppliers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _invoiceRef,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: 'Nº factura o referencia del proveedor',
                      hintText: 'Opcional',
                      helperText:
                          'Se envía como supplierInvoiceReference. Con notas: '
                          'máx. ${PurchaseReceivePayload.maxSupplierInvoiceReferenceLength} '
                          'caracteres en total.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _purchaseNotes,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Notas del documento',
                      hintText: 'Opcional (mismo campo API que la factura)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Forma de pago',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'PAID',
                        label: Text('Contado'),
                        icon: Icon(Icons.payments_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'CREDIT',
                        label: Text('Crédito'),
                        icon: Icon(Icons.schedule_outlined),
                      ),
                      ButtonSegment<String>(
                        value: 'PARTIAL',
                        label: Text('Parcial'),
                        icon: Icon(Icons.pie_chart_outline),
                      ),
                    ],
                    selected: {_paymentStatus},
                    onSelectionChanged: _submitting
                        ? null
                        : (Set<String> next) {
                            setState(() {
                              _paymentStatus = next.first;
                              if (_paymentStatus == 'PAID') {
                                _dueDate = null;
                                _initialPaid.clear();
                              }
                            });
                          },
                  ),
                  if (_paymentStatus == 'CREDIT' ||
                      _paymentStatus == 'PARTIAL') ...[
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Vencimiento (opcional)'),
                      subtitle: Text(
                        _dueDate == null
                            ? 'Sin fecha'
                            : '${_dueDate!.year.toString().padLeft(4, '0')}-'
                                '${_dueDate!.month.toString().padLeft(2, '0')}-'
                                '${_dueDate!.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_today_outlined),
                        onPressed: _submitting
                            ? null
                            : () async {
                                final now = DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _dueDate ?? now,
                                  firstDate: DateTime(now.year - 1),
                                  lastDate: DateTime(now.year + 5),
                                );
                                if (picked != null && mounted) {
                                  setState(() => _dueDate = picked);
                                }
                              },
                      ),
                    ),
                  ],
                  if (_paymentStatus == 'PARTIAL') ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _initialPaid,
                      enabled: !_submitting,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Abono inicial (moneda funcional)',
                        hintText: _functionalCode.isEmpty
                            ? 'Ej. 50.00'
                            : 'En $_functionalCode',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 16),
                if (_functionalCode.isNotEmpty) ...[
                  Text(
                    'Moneda de la factura: $_functionalCode (moneda funcional)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Líneas de la recepción',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Como en el POS: buscá cada producto, cantidad y costo unitario '
                  '(moneda del documento), tocá «Agregar línea». Un solo registro envía '
                  'todas las líneas al servidor.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                if (_lines.isNotEmpty) ...[
                  ..._lines.map(
                    (L) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(
                          L.product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${L.quantity} u. × ${L.unitCost} ${_purchaseDocumentCurrency ?? ''}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _submitting
                              ? null
                              : () => _removeLineByKey(L.lineKey),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_products.isEmpty)
                  const Text('No hay productos activos en catálogo.')
                else ...[
                  Text(
                    'Agregar producto',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  RawAutocomplete<CatalogProduct>(
                    textEditingController: _productField,
                    focusNode: _productFocus,
                    displayStringForOption: _productDisplay,
                    optionsBuilder: (TextEditingValue tv) {
                      final q = tv.text.trim();
                      if (q.isEmpty) return _products.take(45);
                      return _products
                          .where(
                            (p) => searchTextMatchesAnyField(q, [
                              p.name,
                              p.sku,
                              p.barcode,
                            ]),
                          )
                          .take(80);
                    },
                    onSelected: _applyProductSelection,
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            enabled: !_submitting,
                            decoration: const InputDecoration(
                              hintText: 'Nombre, SKU o código de barras',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => onFieldSubmitted(),
                          );
                        },
                    optionsViewBuilder: (context, onSelected, options) {
                      final opts = options.toList();
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 280),
                            child: opts.isEmpty
                                ? const SizedBox.shrink()
                                : ListView.builder(
                                    padding: EdgeInsets.zero,
                                    shrinkWrap: true,
                                    itemCount: opts.length,
                                    itemBuilder: (context, index) {
                                      final p = opts[index];
                                      return ListTile(
                                        dense: true,
                                        title: Text(
                                          p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        subtitle: Text(
                                          _productAutocompleteSubtitle(p),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        onTap: () => onSelected(p),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                  Builder(
                    builder: (context) {
                      final p = _productForCostHint;
                      if (p == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Card(
                          margin: EdgeInsets.zero,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 20,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Costo actual (catálogo)',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _catalogCostSummary(p),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Costo unitario abajo = costo de esta factura '
                                        '(actualiza catálogo al registrar, salvo 0).',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              height: 1.3,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _quantity,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      hintText: 'ej. 24',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _unitCost,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText:
                          'Costo unitario factura (${_purchaseDocumentCurrency ?? "funcional"})',
                      hintText: 'ej. 85.00 (0 = no cambia catálogo)',
                      helperText: _unitCostHelperText,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _addLineToReceipt,
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar línea'),
                  ),
                ],
                if (_formError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _formError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed:
                      _suppliers.isEmpty ||
                          _products.isEmpty ||
                          _lines.isEmpty ||
                          _submitting
                      ? null
                      : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _lines.isEmpty
                              ? 'Registrar compra'
                              : 'Registrar compra (${_lines.length} ${_lines.length == 1 ? 'línea' : 'líneas'})',
                        ),
                ),
              ],
            ),
    );
  }
}
