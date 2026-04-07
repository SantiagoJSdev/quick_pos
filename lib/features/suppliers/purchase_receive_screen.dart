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
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_purchase_receive_entry.dart';
import '../../core/sync/purchase_receive_payload.dart';
import '../../core/sync/sync_cycle.dart';
import 'supplier_form_screen.dart';

final _decimalPositive = RegExp(r'^\d+(\.\d+)?$');

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
  String? _fxLoadError;
  SaleFxPair? _fxPair;
  String? _selectedDocumentCurrency;
  Supplier? _selectedSupplier;
  CatalogProduct? _selectedProduct;

  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _productField = TextEditingController();
  final _productFocus = FocusNode();
  final _supplierField = TextEditingController();
  final _supplierFocus = FocusNode();
  bool _loading = true;
  bool _submitting = false;
  String? _formError;

  String? _purchaseClientId;
  PosTerminalInfo? _terminal;

  @override
  void initState() {
    super.initState();
    PosTerminalInfo.load(widget.localPrefs).then((t) {
      if (mounted) setState(() => _terminal = t);
    });
    _load();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _productField.dispose();
    _productFocus.dispose();
    _supplierField.dispose();
    _supplierFocus.dispose();
    super.dispose();
  }

  Future<List<Supplier>> _loadAllActiveSuppliers() async {
    final all = <Supplier>[];
    String? cursor;
    for (var i = 0; i < 40; i++) {
      final page = await widget.suppliersApi.listSuppliers(
        widget.storeId,
        cursor: cursor,
        limit: 200,
        active: 'true',
      );
      all.addAll(page.items);
      final next = page.nextCursor?.trim();
      if (next == null || next.isEmpty) break;
      cursor = next;
    }
    all.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return all;
  }

  String _supplierDisplay(Supplier s) {
    final t = s.taxId?.trim();
    if (t != null && t.isNotEmpty) return '${s.name} · $t';
    return s.name;
  }

  Supplier? _effectiveSupplier() {
    if (_suppliers.isEmpty) return null;
    final raw = _supplierField.text.trim();
    if (raw.isEmpty) return null;
    final textLower = raw.toLowerCase();
    if (_selectedSupplier != null &&
        _supplierDisplay(_selectedSupplier!).toLowerCase() == textLower) {
      return _selectedSupplier;
    }
    final filtered = _suppliers.where((s) {
      final n = s.name.toLowerCase();
      final tx = (s.taxId ?? '').toLowerCase();
      final ph = (s.phone ?? '').toLowerCase();
      return n.contains(textLower) ||
          tx.contains(textLower) ||
          ph.contains(textLower);
    }).toList();
    if (filtered.length == 1) return filtered.first;
    return null;
  }

  String _productDisplay(CatalogProduct p) {
    final bc = p.barcode?.trim();
    if (bc != null && bc.isNotEmpty) {
      return '${p.name} · ${p.sku} · $bc';
    }
    return '${p.name} · ${p.sku}';
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
    if (s == null || doc == null) {
      _fxPair = null;
      _fxLoadError = null;
      return;
    }
    final func = s.functionalCurrency.code;
    if (func.toUpperCase() == doc.toUpperCase()) {
      _fxPair = null;
      _fxLoadError = null;
      return;
    }
    try {
      _fxPair = await _fetchFxPair(func, doc);
      _fxLoadError = _fxPair == null
          ? 'No hay tasa $func → $doc para esta tienda.'
          : null;
    } catch (e) {
      _fxPair = null;
      _fxLoadError = e.toString();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _contextError = null;
    });
    try {
      final settings =
          await widget.storesApi.getBusinessSettings(widget.storeId);
      final products = await widget.productsApi.listProducts(
        widget.storeId,
        includeInactive: false,
      );
      final suppliers = await _loadAllActiveSuppliers();
      final active =
          products.where((p) => p.active).toList(growable: false);
      active.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _settings = settings;
        _products = active;
        final opts = _documentCurrencyOptions;
        _selectedDocumentCurrency =
            opts.isNotEmpty ? opts.first : settings.functionalCurrency.code;
        _selectedSupplier = suppliers.isNotEmpty ? suppliers.first : null;
        _supplierField.text = _selectedSupplier != null
            ? _supplierDisplay(_selectedSupplier!)
            : '';
        _selectedProduct = active.isNotEmpty ? active.first : null;
        _productField.text =
            _selectedProduct != null ? _productDisplay(_selectedProduct!) : '';
      });
      await _reloadFxForDocumentCurrency();
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

  Future<void> _onDocumentCurrencyChanged(String? code) async {
    if (code == null || code == _selectedDocumentCurrency) return;
    setState(() => _selectedDocumentCurrency = code);
    await _reloadFxForDocumentCurrency();
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    setState(() => _formError = null);
    final s = _settings;
    final doc = _selectedDocumentCurrency;
    if (s == null || doc == null) {
      setState(() => _formError = 'Configuración de tienda no disponible.');
      return;
    }
    if (_supplierField.text.trim().isEmpty) {
      setState(() => _formError = 'Buscá y elegí un proveedor activo.');
      return;
    }
    final sup = _effectiveSupplier();
    if (sup == null) {
      setState(() {
        _formError = 'Proveedor no identificado: tocá una opción de la lista '
            'o dejá una sola coincidencia al filtrar.';
      });
      return;
    }
    setState(() => _selectedSupplier = sup);
    if (_productField.text.trim().isEmpty) {
      setState(() => _formError = 'Buscá y elegí un producto.');
      return;
    }
    final prod = _effectiveProduct();
    if (prod == null) {
      setState(() {
        _formError = 'Producto no identificado: tocá una opción de la lista o '
            'dejá una sola coincidencia al filtrar.';
      });
      return;
    }
    setState(() => _selectedProduct = prod);
    final func = s.functionalCurrency.code;
    if (func.toUpperCase() != doc.toUpperCase() && _fxPair == null) {
      setState(() {
        _formError =
            _fxLoadError ?? 'Definí la tasa del día antes de registrar la compra.';
      });
      return;
    }

    final qty = _quantity.text.trim();
    final cost = _unitCost.text.trim();
    if (!_decimalPositive.hasMatch(qty)) {
      setState(() => _formError = 'Cantidad: número decimal > 0.');
      return;
    }
    final qtyVal = double.tryParse(qty);
    if (qtyVal == null || qtyVal <= 0) {
      setState(() => _formError = 'Cantidad debe ser mayor que 0.');
      return;
    }
    if (!_decimalPositive.hasMatch(cost)) {
      setState(() => _formError = 'Costo unitario (moneda documento): decimal válido.');
      return;
    }
    final costVal = double.tryParse(cost);
    if (costVal == null || costVal <= 0) {
      setState(() => _formError = 'Costo unitario debe ser mayor que 0.');
      return;
    }

    _purchaseClientId ??= ClientMutationId.newId();
    _terminal ??= await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;

    final fxSnap = PurchaseReceivePayload.buildFxSnapshot(
      documentCurrencyCode: doc,
      functionalCurrencyCode: func,
      fxPair: _fxPair,
    );
    final lines = [
      PurchaseReceivePayload.line(
        productId: prod.id,
        quantity: qty,
        unitCost: cost,
      ),
    ];
    final restBody = PurchaseReceivePayload.toRestBody(
      supplierId: sup.id,
      documentCurrencyCode: doc,
      lines: lines,
      fxSnapshot: Map<String, dynamic>.from(fxSnap)..remove('fxSource'),
      clientPurchaseId: _purchaseClientId,
    );

    setState(() => _submitting = true);
    try {
      await widget.purchasesApi.createPurchase(widget.storeId, restBody);
      if (!mounted) return;
      widget.catalogInvalidationBus.invalidateFromLocalMutation(
        productIds: {prod.id},
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
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(PostPurchasePriceHint.afterPurchaseSnackMessage),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      var msg = e.userMessageForSupport;
      if (e.statusCode == 400) {
        final blob = '${e.error} ${e.messages.join(' ')}'.toLowerCase();
        if (blob.contains('inactive') || blob.contains('inactivo')) {
          msg = 'El proveedor está dado de baja. Elegí otro activo o reactivalo '
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
          productIds: {prod.id},
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
      appBar: AppBar(title: const Text('Recepción / compra')),
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
                                'No hay proveedores activos en esta tienda. '
                                'Creá uno con POST /suppliers (solo nombre obligatorio).',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonal(
                                onPressed: () async {
                                  final ok = await Navigator.of(context)
                                      .push<bool>(
                                    MaterialPageRoute(
                                      builder: (ctx) => SupplierFormScreen(
                                        storeId: widget.storeId,
                                        suppliersApi: widget.suppliersApi,
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
                        'Proveedor (activos de esta tienda)',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      RawAutocomplete<Supplier>(
                        textEditingController: _supplierField,
                        focusNode: _supplierFocus,
                        displayStringForOption: _supplierDisplay,
                        optionsBuilder: (TextEditingValue tv) {
                          final q = tv.text.trim().toLowerCase();
                          if (q.isEmpty) return _suppliers.take(45);
                          return _suppliers.where((s) {
                            final n = s.name.toLowerCase();
                            final tx = (s.taxId ?? '').toLowerCase();
                            final ph = (s.phone ?? '').toLowerCase();
                            return n.contains(q) ||
                                tx.contains(q) ||
                                ph.contains(q);
                          }).take(80);
                        },
                        onSelected: (s) {
                          setState(() {
                            _selectedSupplier = s;
                            _supplierField.text = _supplierDisplay(s);
                          });
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              hintText:
                                  'Nombre, taxId o teléfono',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => onFieldSubmitted(),
                          );
                        },
                        optionsViewBuilder:
                            (context, onSelected, options) {
                          final opts = options.toList();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 280),
                                child: opts.isEmpty
                                    ? const SizedBox.shrink()
                                    : ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: opts.length,
                                        itemBuilder: (context, index) {
                                          final s = opts[index];
                                          return ListTile(
                                            dense: true,
                                            title: Text(
                                              s.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              [
                                                if (s.taxId != null &&
                                                    s.taxId!.trim().isNotEmpty)
                                                  'taxId: ${s.taxId}',
                                                if (s.phone != null &&
                                                    s.phone!.trim().isNotEmpty)
                                                  s.phone!,
                                              ].where((x) => x.isNotEmpty).join(' · '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () => onSelected(s),
                                          );
                                        },
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_products.isEmpty)
                      const Text('No hay productos activos en catálogo.')
                    else ...[
                      Text(
                        'Producto',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      RawAutocomplete<CatalogProduct>(
                        textEditingController: _productField,
                        focusNode: _productFocus,
                        displayStringForOption: _productDisplay,
                        optionsBuilder: (TextEditingValue tv) {
                          final q = tv.text.trim().toLowerCase();
                          if (q.isEmpty) return _products.take(45);
                          return _products.where((p) {
                            final n = p.name.toLowerCase();
                            final s = p.sku.toLowerCase();
                            final b = (p.barcode ?? '').toLowerCase();
                            return n.contains(q) ||
                                s.contains(q) ||
                                b.contains(q);
                          }).take(80);
                        },
                        onSelected: (p) {
                          setState(() {
                            _selectedProduct = p;
                            _productField.text = _productDisplay(p);
                          });
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              hintText:
                                  'Escribí nombre, SKU o código de barras',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => onFieldSubmitted(),
                          );
                        },
                        optionsViewBuilder:
                            (context, onSelected, options) {
                          final opts = options.toList();
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 6,
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 280),
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
                                              '${p.sku}${p.barcode != null && p.barcode!.isNotEmpty ? ' · ${p.barcode}' : ''}',
                                              maxLines: 1,
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
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _quantity,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        hintText: 'ej. 24',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _unitCost,
                      decoration: InputDecoration(
                        labelText:
                            'Costo unitario (${_selectedDocumentCurrency ?? "—"})',
                        hintText: 'ej. 85.00',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_documentCurrencyOptions.length > 1) ...[
                      Text(
                        'Moneda del documento',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        value: _selectedDocumentCurrency,
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
                    if (_functionalCode.isNotEmpty &&
                        _selectedDocumentCurrency != null &&
                        _functionalCode.toUpperCase() !=
                            _selectedDocumentCurrency!.toUpperCase()) ...[
                      const SizedBox(height: 8),
                      Text(
                        _fxPair == null
                            ? (_fxLoadError ?? 'Sin tasa de cambio.')
                            : 'Ref.: 1 $_functionalCode = ${SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(functionalCode: _functionalCode, documentCode: _selectedDocumentCurrency!, pair: _fxPair)} ${_selectedDocumentCurrency!}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
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
                      onPressed: _suppliers.isEmpty ||
                              _products.isEmpty ||
                              _submitting
                          ? null
                          : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Registrar compra'),
                    ),
                  ],
                ),
    );
  }
}
