import 'package:flutter/material.dart';

import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/purchases_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/widgets/quickmarket_branding.dart';
import '../sale/pos_sale_ui_tokens.dart';
import 'payables_screen.dart';
import 'purchase_receive_screen.dart';
import 'purchases_list_screen.dart';
import 'supplier_form_screen.dart';
import 'suppliers_list_screen.dart';

/// Hub **Proveedores**: lista de proveedores, facturas y deuda.
class SuppliersModuleScreen extends StatefulWidget {
  const SuppliersModuleScreen({
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
  State<SuppliersModuleScreen> createState() => _SuppliersModuleScreenState();
}

class _SuppliersModuleScreenState extends State<SuppliersModuleScreen> {
  int _tab = 0;
  int _suppliersReloadToken = 0;
  int _purchasesReloadToken = 0;

  Future<void> _onFab() async {
    if (_tab == 0) {
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (ctx) => SupplierFormScreen(
            storeId: widget.storeId,
            suppliersApi: widget.suppliersApi,
            localPrefs: widget.localPrefs,
            shellOnline: widget.shellOnline,
          ),
        ),
      );
      if (ok == true && mounted) {
        setState(() => _suppliersReloadToken++);
      }
      return;
    }
    if (_tab == 1) {
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
      if (ok == true && mounted) {
        setState(() => _purchasesReloadToken++);
      }
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
      ),
      floatingActionButton: _tab == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: _onFab,
              icon: const Icon(Icons.add),
              label: Text(_tab == 0 ? 'Proveedor' : 'Nueva factura'),
            ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Lista'),
                  icon: Icon(Icons.local_shipping_outlined),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Facturas'),
                  icon: Icon(Icons.receipt_long_outlined),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text('Deuda'),
                  icon: Icon(Icons.account_balance_wallet_outlined),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (Set<int> next) {
                setState(() => _tab = next.first);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              _tab == 0
                  ? 'Alta y edición de proveedores. El ajuste de stock suelto sigue en Inventario.'
                  : _tab == 1
                      ? 'Facturas completas: contado, crédito o parcial. Abonos desde el detalle.'
                      : 'Saldos pendientes por proveedor (payables).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PosSaleUi.textMuted,
                  ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                SuppliersListScreen(
                  key: ValueKey('suppliers_list_$_suppliersReloadToken'),
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
                  embeddedInModule: true,
                ),
                PurchasesListScreen(
                  key: ValueKey('purchases_list_$_purchasesReloadToken'),
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
                  embeddedInModule: true,
                  hideFab: true,
                ),
                PayablesScreen(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
