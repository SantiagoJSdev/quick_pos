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
import '../../core/models/supplier.dart';
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

  /// `OPEN` | `PAID` | `CREDIT` | `PARTIAL` | `VOID` | null = todas.
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
  final _search = TextEditingController();
  Timer? _debounce;
  List<PurchaseSummary> _items = [];
  List<Supplier> _suppliers = [];
  String? _supplierIdFilter;
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _loadingSuppliers = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialPaymentFilter;
    _supplierIdFilter = widget.initialSupplierId;
    _search.addListener(_onSearchChanged);
    unawaited(_loadSuppliers());
    unawaited(_load(reset: true));
  }

  @override
  void didUpdateWidget(covariant PurchasesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shellOnline && widget.shellOnline) {
      unawaited(_loadSuppliers());
      unawaited(_load(reset: true));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.removeListener(_onSearchChanged);
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadSuppliers() async {
    if (!widget.shellOnline) return;
    setState(() => _loadingSuppliers = true);
    try {
      final page = await widget.suppliersApi.listSuppliers(
        widget.storeId,
        limit: 100,
        active: 'all',
      );
      if (!mounted) return;
      setState(() {
        _suppliers = page.items;
        _loadingSuppliers = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSuppliers = false);
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
      final isVoidFilter = _filter == 'VOID';
      final page = await widget.purchasesApi.listPurchases(
        widget.storeId,
        supplierId: _supplierIdFilter,
        paymentStatus: isVoidFilter ? null : _filter,
        status: isVoidFilter ? 'VOID' : null,
        includeVoided: isVoidFilter ? true : null,
        cursor: reset ? null : _nextCursor,
        limit: 50,
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

  /// Filtro local por Nº factura y/o nombre de proveedor (el API no tiene `q`).
  List<PurchaseSummary> get _visibleItems {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items.where((p) {
      final ref = (p.supplierInvoiceReference ?? '').toLowerCase();
      final name = (p.supplierName ?? '').toLowerCase();
      final id = p.id.toLowerCase();
      return ref.contains(q) || name.contains(q) || id.contains(q);
    }).toList();
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

  String _invoiceNumberLabel(PurchaseSummary p) {
    final ref = p.supplierInvoiceReference?.trim();
    if (ref != null && ref.isNotEmpty) return ref;
    return 'Sin Nº de factura';
  }

  String _subtitleFor(PurchaseSummary p) {
    final parts = <String>[];
    final name = p.supplierName?.trim();
    if (name != null && name.isNotEmpty) {
      parts.add(name);
    } else if (p.supplierId.isNotEmpty) {
      parts.add('Proveedor');
    }
    if (p.isVoided) {
      parts.add('ANULADA');
    } else {
      final status = p.paymentStatus?.toUpperCase();
      if (status != null && status.isNotEmpty) parts.add(status);
    }
    final total = p.totalFunctional ?? p.totalDocument;
    if (total != null && total.isNotEmpty) {
      parts.add('Total $total');
    }
    final due = p.amountDueFunctional;
    if (!p.isVoided && due != null && due.isNotEmpty) {
      final dueN = double.tryParse(due) ?? 0;
      if (dueN > 0) parts.add('Saldo $due');
    }
    final created = p.createdAt?.trim();
    if (created != null && created.isNotEmpty) {
      parts.add(
        created.length >= 10 ? created.substring(0, 10) : created,
      );
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  bool get _supplierFilterLocked =>
      widget.initialSupplierId != null &&
      widget.initialSupplierId!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Buscar por Nº factura o proveedor',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Proveedor',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  value: _supplierIdFilter,
                  hint: Text(
                    _loadingSuppliers ? 'Cargando…' : 'Todos los proveedores',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos los proveedores'),
                    ),
                    ..._suppliers.map(
                      (s) => DropdownMenuItem<String?>(
                        value: s.id,
                        child: Text(
                          s.active ? s.name : '${s.name} (inactivo)',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: _supplierFilterLocked || _loading
                      ? null
                      : (id) {
                          setState(() => _supplierIdFilter = id);
                          unawaited(_load(reset: true));
                        },
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
                  ('VOID', 'Anuladas'),
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
          if (!_loading && _items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                _search.text.trim().isEmpty
                    ? '${_items.length} factura${_items.length == 1 ? '' : 's'}'
                    : '${visible.length} de ${_items.length} (filtro local)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PosSaleUi.textMuted,
                    ),
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
                                style: const TextStyle(color: PosSaleUi.textMuted),
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
                        child: visible.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  const SizedBox(height: 80),
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Text(
                                        _items.isEmpty
                                            ? 'No hay facturas con este filtro.\n'
                                                'Creá una con «Nueva factura».'
                                            : 'Ninguna factura coincide con la búsqueda.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: PosSaleUi.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 88),
                                itemCount: visible.length +
                                    (_nextCursor != null &&
                                            _search.text.trim().isEmpty
                                        ? 1
                                        : 0),
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: PosSaleUi.divider,
                                ),
                                itemBuilder: (context, i) {
                                  if (i >= visible.length) {
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
                                  final p = visible[i];
                                  final hasRef = (p.supplierInvoiceReference ?? '')
                                      .trim()
                                      .isNotEmpty;
                                  return ListTile(
                                    leading: Icon(
                                      p.isVoided
                                          ? Icons.block
                                          : p.isOpen
                                              ? Icons.receipt_long_outlined
                                              : Icons.check_circle_outline,
                                      color: p.isVoided
                                          ? Colors.redAccent
                                          : p.isOpen
                                              ? Colors.orange
                                              : Colors.green,
                                    ),
                                    title: Text(
                                      hasRef
                                          ? 'Nº ${_invoiceNumberLabel(p)}'
                                          : _invoiceNumberLabel(p),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: hasRef
                                            ? PosSaleUi.text
                                            : PosSaleUi.textMuted,
                                      ),
                                    ),
                                    subtitle: Text(_subtitleFor(p)),
                                    isThreeLine: true,
                                    trailing: const Icon(Icons.chevron_right),
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
