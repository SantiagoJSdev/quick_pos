import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/purchases_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/models/purchase.dart';
import '../../core/storage/local_prefs.dart';
import '../sale/pos_sale_ui_tokens.dart';
import 'purchase_detail_screen.dart';
import 'purchase_receive_screen.dart';

/// Listado de facturas / compras (`GET /purchases`).
class PurchasesListScreen extends StatefulWidget {
  const PurchasesListScreen({
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
    this.shellOnline = true,
    this.initialPaymentFilter,
    this.initialSupplierId,
    this.embeddedInModule = true,
    this.hideFab = false,
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
  final bool shellOnline;

  /// `OPEN` | `PAID` | `CREDIT` | `PARTIAL` | null = todas.
  final String? initialPaymentFilter;
  final String? initialSupplierId;

  /// false cuando se abre como ruta (ej. desde Deuda) → muestra AppBar.
  final bool embeddedInModule;

  /// Oculta FAB (lo maneja [SuppliersModuleScreen]).
  final bool hideFab;

  @override
  State<PurchasesListScreen> createState() => _PurchasesListScreenState();
}

class _PurchasesListScreenState extends State<PurchasesListScreen> {
  late String? _filter;
  List<PurchaseSummary> _items = [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialPaymentFilter;
    unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant PurchasesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shellOnline && widget.shellOnline) {
      unawaited(_load(reset: true));
    }
  }

  Future<void> _load({required bool reset}) async {
    if (!widget.shellOnline) {
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error =
            'Facturas requieren conexión. Conectate para ver el listado.';
        if (reset) _items = [];
      });
      return;
    }
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextCursor = null;
      });
    } else {
      if (_nextCursor == null || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final page = await widget.purchasesApi.listPurchases(
        widget.storeId,
        supplierId: widget.initialSupplierId,
        paymentStatus: _filter,
        cursor: reset ? null : _nextCursor,
      );
      if (!mounted) return;
      setState(() {
        _items = reset ? page.items : [..._items, ...page.items];
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.userMessageForSupport;
        if (reset) _items = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
        if (reset) _items = [];
      });
    }
  }

  Future<void> _openNewInvoice() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => PurchaseReceiveScreen(
          storeId: widget.storeId,
          localPrefs: widget.localPrefs,
          storesApi: widget.storesApi,
          exchangeRatesApi: widget.exchangeRatesApi,
          productsApi: widget.productsApi,
          purchasesApi: widget.purchasesApi,
          suppliersApi: widget.suppliersApi,
          syncApi: widget.syncApi,
          catalogInvalidationBus: widget.catalogInvalidationBus,
        ),
      ),
    );
    if (ok == true && mounted) await _load(reset: true);
  }

  Future<void> _openDetail(PurchaseSummary p) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => PurchaseDetailScreen(
          storeId: widget.storeId,
          purchaseId: p.id,
          purchasesApi: widget.purchasesApi,
          shellOnline: widget.shellOnline,
        ),
      ),
    );
    if (changed == true && mounted) await _load(reset: true);
  }

  String _titleFor(PurchaseSummary p) {
    final ref = p.supplierInvoiceReference?.trim();
    if (ref != null && ref.isNotEmpty) return ref;
    return '#${p.id.length > 8 ? p.id.substring(0, 8) : p.id}';
  }

  String _subtitleFor(PurchaseSummary p) {
    final parts = <String>[];
    final name = p.supplierName?.trim();
    if (name != null && name.isNotEmpty) parts.add(name);
    final status = p.paymentStatus?.toUpperCase();
    if (status != null && status.isNotEmpty) parts.add(status);
    final due = p.amountDueFunctional;
    if (due != null && due.isNotEmpty) parts.add('Saldo $due');
    final total = p.totalFunctional ?? p.totalDocument;
    if (total != null && total.isNotEmpty) {
      final cur = p.documentCurrencyCode ?? '';
      parts.add('Total $total${cur.isEmpty ? '' : ' $cur'}');
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embeddedInModule
          ? null
          : AppBar(
              title: Text(
                widget.initialSupplierId == null
                    ? 'Facturas'
                    : 'Facturas del proveedor',
              ),
            ),
      floatingActionButton: widget.hideFab
          ? null
          : FloatingActionButton.extended(
              heroTag: 'fab_purchases_list',
              onPressed: _openNewInvoice,
              icon: const Icon(Icons.add),
              label: const Text('Nueva factura'),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.shellOnline)
            Material(
              color: const Color(0xFF3A2F1A),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Sin conexión: no se puede cargar el listado de facturas.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.orangeAccent,
                      ),
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                for (final e in const [
                  (null, 'Todas'),
                  ('OPEN', 'Abiertas'),
                  ('PAID', 'Pagadas'),
                  ('CREDIT', 'Crédito'),
                  ('PARTIAL', 'Parcial'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.$2),
                      selected: _filter == e.$1,
                      onSelected: (_) {
                        setState(() => _filter = e.$1);
                        unawaited(_load(reset: true));
                      },
                    ),
                  ),
                IconButton(
                  tooltip: 'Recargar',
                  onPressed: _loading ? null : () => _load(reset: true),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: PosSaleUi.textMuted),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => _load(reset: true),
                                child: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _load(reset: true),
                        child: _items.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 80),
                                  Center(
                                    child: Text(
                                      'No hay facturas con este filtro.',
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount:
                                    _items.length + (_nextCursor != null ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (i >= _items.length) {
                                    if (!_loadingMore) {
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        unawaited(_load(reset: false));
                                      });
                                    }
                                    return const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  final p = _items[i];
                                  return ListTile(
                                    leading: Icon(
                                      p.isOpen
                                          ? Icons.receipt_long_outlined
                                          : Icons.check_circle_outline,
                                      color: p.isOpen
                                          ? Colors.orange
                                          : Colors.green,
                                    ),
                                    title: Text(_titleFor(p)),
                                    subtitle: Text(_subtitleFor(p)),
                                    onTap: () => _openDetail(p),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
