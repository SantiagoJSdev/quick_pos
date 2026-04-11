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
import '../../core/models/local_supplier.dart';
import '../../core/models/supplier.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/widgets/quickmarket_branding.dart';
import '../sale/pos_sale_ui_tokens.dart';
import 'purchase_receive_screen.dart';
import 'supplier_form_screen.dart';

/// Lista de proveedores vía `GET /suppliers` (búsqueda `q`, paginación, filtro activos).
class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({
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

  /// Desde [MainShell]: lista desde caché local sin esperar red.
  final bool shellOnline;

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Supplier> _list = [];
  String? _nextCursor;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _includeInactive = false;

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearchChanged);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant SuppliersListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shellOnline && widget.shellOnline) {
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
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load(reset: true);
    });
  }

  String get _activeParam => _includeInactive ? 'all' : 'true';

  Future<void> _load({required bool reset}) async {
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
    if (!widget.shellOnline) {
      if (!reset) {
        if (mounted) setState(() => _loadingMore = false);
        return;
      }
      final local = await widget.localPrefs.getLocalSuppliers();
      if (!mounted) return;
      final q = _search.text.trim().toLowerCase();
      var mapped = local
          .map(
            (x) => Supplier(
              id: x.id,
              storeId: widget.storeId,
              name: x.name,
              active: true,
            ),
          )
          .toList();
      if (q.isNotEmpty) {
        mapped = mapped
            .where((s) => s.name.toLowerCase().contains(q))
            .toList();
      }
      setState(() {
        _list = mapped;
        _error = local.isEmpty
            ? 'Sin proveedores en caché. Conectate para sincronizar.'
            : null;
        _loading = false;
        _loadingMore = false;
        _nextCursor = null;
      });
      return;
    }
    try {
      final page = await widget.suppliersApi.listSuppliers(
        widget.storeId,
        q: _search.text.trim().isEmpty ? null : _search.text.trim(),
        cursor: reset ? null : _nextCursor,
        limit: 50,
        active: _activeParam,
      );
      if (!mounted) return;
      await widget.localPrefs.saveLocalSuppliers(
        page.items
            .map((e) => LocalSupplier(id: e.id, name: e.name))
            .toList(),
      );
      setState(() {
        if (reset) {
          _list = page.items;
        } else {
          _list = [..._list, ...page.items];
        }
        _nextCursor = page.nextCursor;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiError catch (e) {
      final local = await widget.localPrefs.getLocalSuppliers();
      if (!mounted) return;
      if (reset && local.isNotEmpty) {
        setState(() {
          _list = local
              .map(
                (x) => Supplier(
                  id: x.id,
                  storeId: widget.storeId,
                  name: x.name,
                  active: true,
                ),
              )
              .toList();
          _error = null;
          _loading = false;
          _loadingMore = false;
          _nextCursor = null;
        });
      } else {
        setState(() {
          if (reset) _list = [];
          _error = e.userMessageForSupport;
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (e) {
      final local = await widget.localPrefs.getLocalSuppliers();
      if (!mounted) return;
      if (reset && local.isNotEmpty) {
        setState(() {
          _list = local
              .map(
                (x) => Supplier(
                  id: x.id,
                  storeId: widget.storeId,
                  name: x.name,
                  active: true,
                ),
              )
              .toList();
          _error = null;
          _loading = false;
          _loadingMore = false;
          _nextCursor = null;
        });
      } else {
        setState(() {
          if (reset) _list = [];
          _error = e.toString();
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _openForm({Supplier? existing}) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => SupplierFormScreen(
          storeId: widget.storeId,
          suppliersApi: widget.suppliersApi,
          existing: existing,
        ),
      ),
    );
    if (ok == true && mounted) await _load(reset: true);
  }

  Future<void> _openPurchaseReceive() async {
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

  String _subtitleFor(Supplier s) {
    final parts = <String>[];
    if (!s.active) parts.add('Inactivo');
    if (s.taxId != null && s.taxId!.trim().isNotEmpty) {
      parts.add('taxId: ${s.taxId}');
    }
    if (s.phone != null && s.phone!.trim().isNotEmpty) {
      parts.add(s.phone!);
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Future<void> _confirmDeactivate(Supplier s) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Dar de baja proveedor'),
        content: Text(
          '¿Desactivar "${s.name}"? No podrá usarse en nuevas compras hasta reactivarlo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    try {
      await widget.suppliersApi.deactivateSupplier(widget.storeId, s.id);
      if (mounted) await _load(reset: true);
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessageForSupport)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        title: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 12, right: 10),
              child: QuickMarketLogoMark(size: 32, borderRadius: 10),
            ),
            Text(
              'Proveedores',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: PosSaleUi.text,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: _loading ? null : _openPurchaseReceive,
            tooltip: 'Recepción / compra',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : () => _load(reset: true),
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, taxId o teléfono',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ),
          SwitchListTile(
            title: const Text('Incluir dados de baja'),
            subtitle: const Text(
              'Lista activos por defecto (`active=true`). Marcá esto para ver inactivos y reactivarlos al editar.',
            ),
            value: _includeInactive,
            onChanged: _loading
                ? null
                : (v) {
                    setState(() => _includeInactive = v);
                    _load(reset: true);
                  },
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _list.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
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
                    : _list.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No hay proveedores para esta tienda.\n\n'
                                'Creá uno con el botón + (POST /suppliers). '
                                'Cada tienda tiene su propia lista.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(color: PosSaleUi.textMuted),
                              ),
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (n) {
                              if (n.metrics.pixels >
                                      n.metrics.maxScrollExtent - 120 &&
                                  !_loadingMore &&
                                  _nextCursor != null) {
                                _load(reset: false);
                              }
                              return false;
                            },
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(0, 0, 0, 88),
                              itemCount: _list.length + (_loadingMore ? 1 : 0),
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                height: 1,
                                color: PosSaleUi.divider,
                              ),
                              itemBuilder: (context, i) {
                                if (i >= _list.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final s = _list[i];
                                return ListTile(
                                  title: Text(
                                    s.name,
                                    style: const TextStyle(
                                      color: PosSaleUi.text,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    _subtitleFor(s),
                                    style: const TextStyle(
                                      color: PosSaleUi.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  onTap: () => _openForm(existing: s),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (v) {
                                      if (v == 'deactivate' && s.active) {
                                        _confirmDeactivate(s);
                                      }
                                    },
                                    itemBuilder: (ctx) => [
                                      if (s.active)
                                        const PopupMenuItem(
                                          value: 'deactivate',
                                          child: Text('Dar de baja'),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Proveedor'),
      ),
    );
  }
}
