import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/purchases_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/business_settings.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/local_supplier.dart';
import '../../core/network/network_errors.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/pos/sale_checkout_payload.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_purchase_receive_entry.dart';
import '../../core/sync/purchase_receive_payload.dart';
import '../../core/sync/sync_cycle.dart';

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
    required this.syncApi,
    required this.catalogInvalidationBus,
  });

  final String storeId;
  final LocalPrefs localPrefs;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final ProductsApi productsApi;
  final PurchasesApi purchasesApi;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;

  @override
  State<PurchaseReceiveScreen> createState() => _PurchaseReceiveScreenState();
}

class _PurchaseReceiveScreenState extends State<PurchaseReceiveScreen> {
  List<LocalSupplier> _suppliers = [];
  List<CatalogProduct> _products = [];
  BusinessSettings? _settings;
  String? _contextError;
  String? _fxLoadError;
  SaleFxPair? _fxPair;
  String? _selectedDocumentCurrency;
  LocalSupplier? _selectedSupplier;
  CatalogProduct? _selectedProduct;

  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
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
      final suppliers = await widget.localPrefs.getLocalSuppliers();
      suppliers.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      final settings =
          await widget.storesApi.getBusinessSettings(widget.storeId);
      final products = await widget.productsApi.listProducts(
        widget.storeId,
        includeInactive: false,
      );
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
        _selectedProduct = active.isNotEmpty ? active.first : null;
      });
      await _reloadFxForDocumentCurrency();
      if (mounted) setState(() => _loading = false);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _contextError = e.userMessage;
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
    final sup = _selectedSupplier;
    final prod = _selectedProduct;
    if (s == null || doc == null) {
      setState(() => _formError = 'Configuración de tienda no disponible.');
      return;
    }
    if (sup == null) {
      setState(() => _formError = 'Elegí un proveedor (lista local).');
      return;
    }
    if (prod == null) {
      setState(() => _formError = 'Elegí un producto.');
      return;
    }
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
        const SnackBar(content: Text('Compra registrada.')),
      );
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _formError = e.userMessage);
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
                          child: Text(
                            'No hay proveedores locales. Volvé a Proveedores y cargá al menos un UUID.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      )
                    else ...[
                      Text(
                        'Proveedor',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<LocalSupplier>(
                        isExpanded: true,
                        value: _selectedSupplier,
                        items: _suppliers
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(s.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedSupplier = v),
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
                      DropdownButton<CatalogProduct>(
                        isExpanded: true,
                        value: _selectedProduct,
                        items: _products
                            .map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(
                                  '${p.name} · ${p.sku}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedProduct = v),
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
