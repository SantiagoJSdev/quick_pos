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
import 'purchases_list_screen.dart';

/// Deuda por proveedor (`GET /purchases/payables`).
class PayablesScreen extends StatefulWidget {
  const PayablesScreen({
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
  final bool shellOnline;

  @override
  State<PayablesScreen> createState() => _PayablesScreenState();
}

class _PayablesScreenState extends State<PayablesScreen> {
  List<PayableRow> _rows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant PayablesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.shellOnline && widget.shellOnline) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (!widget.shellOnline) {
      setState(() {
        _loading = false;
        _rows = [];
        _error = 'La deuda requiere conexión.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.purchasesApi.listPayables(widget.storeId);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessageForSupport;
        _rows = [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _rows = [];
      });
    }
  }

  double get _totalDue {
    var t = 0.0;
    for (final r in _rows) {
      t += double.tryParse(r.amountDueFunctional) ?? 0;
    }
    return t;
  }

  Future<void> _openSupplierPurchases(PayableRow row) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (ctx) => PurchasesListScreen(
          storeId: widget.storeId,
          localPrefs: widget.localPrefs,
          storesApi: widget.storesApi,
          exchangeRatesApi: widget.exchangeRatesApi,
          productsApi: widget.productsApi,
          purchasesApi: widget.purchasesApi,
          suppliersApi: widget.suppliersApi,
          syncApi: widget.syncApi,
          catalogInvalidationBus: widget.catalogInvalidationBus,
          shellOnline: widget.shellOnline,
          initialPaymentFilter: 'OPEN',
          initialSupplierId: row.supplierId,
          embeddedInModule: false,
        ),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.shellOnline)
          Material(
            color: const Color(0xFF3A2F1A),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                'Sin conexión: no se puede consultar la deuda.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.orangeAccent,
                    ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _rows.isEmpty
                      ? 'Deuda a proveedores'
                      : 'Deuda total: ${_totalDue.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'Recargar',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _rows.isEmpty
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
                              onPressed: _load,
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _rows.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 80),
                                Center(
                                  child: Text(
                                    'No hay saldos pendientes.',
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: _rows.length,
                              itemBuilder: (context, i) {
                                final r = _rows[i];
                                final count = r.openPurchasesCount;
                                return ListTile(
                                  leading: const Icon(
                                    Icons.account_balance_wallet_outlined,
                                  ),
                                  title: Text(r.supplierName),
                                  subtitle: Text(
                                    count == null
                                        ? 'Saldo pendiente'
                                        : '$count factura${count == 1 ? '' : 's'} abierta${count == 1 ? '' : 's'}',
                                  ),
                                  trailing: Text(
                                    r.amountDueFunctional,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  onTap: () => _openSupplierPurchases(r),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}
