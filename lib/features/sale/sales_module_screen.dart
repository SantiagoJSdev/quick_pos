import 'package:flutter/material.dart';

import '../../core/api/exchange_rates_api.dart';
import '../../core/api/products_api.dart';
import '../../core/api/sale_returns_api.dart';
import '../../core/api/sales_api.dart';
import '../../core/api/stores_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/widgets/quickmarket_branding.dart';
import 'pos_sale_screen.dart';
import 'pos_sale_ui_tokens.dart';
import 'product_price_lookup_screen.dart';
import 'sale_return_screen.dart';
import 'ticket_history_screen.dart';

/// Pestaña **Venta**: menú → POS / historial / consulta de precios (misma estética oscura del POS).
class SalesModuleScreen extends StatelessWidget {
  const SalesModuleScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
    required this.storesApi,
    required this.exchangeRatesApi,
    required this.salesApi,
    required this.saleReturnsApi,
    required this.syncApi,
    required this.catalogInvalidationBus,
    required this.localPrefs,
  });

  final String storeId;
  final ProductsApi productsApi;
  final StoresApi storesApi;
  final ExchangeRatesApi exchangeRatesApi;
  final SalesApi salesApi;
  final SaleReturnsApi saleReturnsApi;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;
  final LocalPrefs localPrefs;

  @override
  Widget build(BuildContext context) {
    return Navigator(
        initialRoute: '/',
        onGenerateRoute: (RouteSettings settings) {
          if (settings.name == '/') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (navCtx) => _VentasMenuPage(
                onOpenPos: () {
                  Navigator.of(navCtx).push<void>(
                    MaterialPageRoute<void>(
                      builder: (c) => PosSaleScreen(
                        storeId: storeId,
                        productsApi: productsApi,
                        storesApi: storesApi,
                        exchangeRatesApi: exchangeRatesApi,
                        salesApi: salesApi,
                        syncApi: syncApi,
                        catalogInvalidationBus: catalogInvalidationBus,
                        localPrefs: localPrefs,
                        onRequestExit: () => Navigator.of(c).pop(),
                      ),
                    ),
                  );
                },
                onOpenHistorial: () {
                  Navigator.of(navCtx).push<void>(
                    MaterialPageRoute<void>(
                      builder: (c) => TicketHistoryScreen(
                        storeId: storeId,
                        localPrefs: localPrefs,
                        salesApi: salesApi,
                      ),
                    ),
                  );
                },
                onOpenPrecios: () {
                  Navigator.of(navCtx).push<void>(
                    MaterialPageRoute<void>(
                      builder: (c) => ProductPriceLookupScreen(
                        storeId: storeId,
                        productsApi: productsApi,
                      ),
                    ),
                  );
                },
                onOpenDevolucion: () {
                  Navigator.of(navCtx).push<void>(
                    MaterialPageRoute<void>(
                      builder: (c) => SaleReturnScreen(
                        storeId: storeId,
                        salesApi: salesApi,
                        saleReturnsApi: saleReturnsApi,
                        storesApi: storesApi,
                        exchangeRatesApi: exchangeRatesApi,
                        localPrefs: localPrefs,
                        syncApi: syncApi,
                        catalogInvalidationBus: catalogInvalidationBus,
                      ),
                    ),
                  );
                },
              ),
            );
          }
          return null;
        },
    );
  }
}

class _VentasMenuPage extends StatelessWidget {
  const _VentasMenuPage({
    required this.onOpenPos,
    required this.onOpenHistorial,
    required this.onOpenPrecios,
    required this.onOpenDevolucion,
  });

  final VoidCallback onOpenPos;
  final VoidCallback onOpenHistorial;
  final VoidCallback onOpenPrecios;
  final VoidCallback onOpenDevolucion;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosSaleUi.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            const QuickMarketModuleHeader(
              moduleLabel: 'Ventas',
              subtitle: 'Elegí una opción',
            ),
            const SizedBox(height: 28),
            _VentasTile(
              icon: Icons.shopping_cart_outlined,
              title: 'POS — Facturar ticket',
              subtitle: 'Buscar productos, escanear y cobrar como siempre',
              onTap: onOpenPos,
            ),
            const SizedBox(height: 12),
            _VentasTile(
              icon: Icons.history,
              title: 'Historial de tickets',
              subtitle:
                  'Hoy en este dispositivo o consulta general por fechas en el servidor',
              onTap: onOpenHistorial,
            ),
            const SizedBox(height: 12),
            _VentasTile(
              icon: Icons.undo_outlined,
              title: 'Devolución de venta',
              subtitle:
                  'UUID de venta, cantidades por línea; sin red va a la cola sync',
              onTap: onOpenDevolucion,
            ),
            const SizedBox(height: 12),
            _VentasTile(
              icon: Icons.price_change_outlined,
              title: 'Buscar precio de producto',
              subtitle: 'Consulta precio de lista sin armar ticket',
              onTap: onOpenPrecios,
            ),
          ],
        ),
      ),
    );
  }
}

class _VentasTile extends StatelessWidget {
  const _VentasTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PosSaleUi.surface2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: PosSaleUi.primaryDim,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: PosSaleUi.primary.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(icon, color: PosSaleUi.primary, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: PosSaleUi.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: PosSaleUi.textMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: PosSaleUi.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
