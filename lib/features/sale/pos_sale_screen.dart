import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/models/catalog_product.dart';
import '../../core/models/pos_cart_line.dart';
import 'barcode_scanner_screen.dart';

bool get _scannerSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

CatalogProduct? _findByBarcode(List<CatalogProduct> products, String raw) {
  final c = raw.trim().toLowerCase();
  if (c.isEmpty) return null;
  for (final p in products) {
    final b = p.barcode?.trim().toLowerCase();
    if (b != null && b.isNotEmpty && b == c) return p;
  }
  return null;
}

/// P1 — catálogo de venta: lista, búsqueda, escaneo por `product.barcode`, carrito mínimo.
class PosSaleScreen extends StatefulWidget {
  const PosSaleScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
  });

  final String storeId;
  final ProductsApi productsApi;

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen> {
  final _search = TextEditingController();
  List<CatalogProduct> _all = [];
  final List<PosCartLine> _cart = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.productsApi.listProducts(widget.storeId);
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _error = e.userMessage;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<CatalogProduct> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void _addProductToCart(CatalogProduct p, {int qty = 1}) {
    final i = _cart.indexWhere((l) => l.productId == p.id);
    setState(() {
      if (i >= 0) {
        _cart[i].quantity += qty;
      } else {
        _cart.add(
          PosCartLine(
            productId: p.id,
            name: p.name,
            sku: p.sku,
            unitPrice: p.price,
            currency: p.currency,
            quantity: qty,
          ),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${p.name} × $qty en el ticket')),
    );
  }

  Future<void> _openScanner() async {
    if (!_scannerSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El escáner solo está disponible en Android e iOS.'),
        ),
      );
      return;
    }
    final code = await BarcodeScannerScreen.open(context);
    if (!mounted || code == null || code.isEmpty) return;

    final p = _findByBarcode(_all, code);
    if (p != null) {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (ctx) {
          var q = 1;
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
                        _addProductToCart(p, qty: q);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ningún producto activo con código "$code". '
            'Buscá en Catálogo o cargá el código de barras en la ficha del producto.',
          ),
        ),
      );
    }
  }

  int get _cartUnits =>
      _cart.fold<int>(0, (sum, l) => sum + l.quantity);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Venta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear código',
            onPressed: _loading ? null : _openScanner,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, SKU o código de barras',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              autocorrect: false,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_error!, textAlign: TextAlign.center),
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
                        child: _filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.2,
                                  ),
                                  Text(
                                    _all.isEmpty
                                        ? 'No hay productos activos. Cargalos en Inventario → Catálogo.'
                                        : 'Sin resultados.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                                itemCount: _filtered.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final p = _filtered[i];
                                  return ListTile(
                                    title: Text(p.name),
                                    subtitle: Text(
                                      'SKU ${p.sku}'
                                      '${p.barcode != null && p.barcode!.isNotEmpty ? ' · ${p.barcode}' : ''}',
                                    ),
                                    trailing: Text(
                                      '${p.price} ${p.currency}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall,
                                    ),
                                    onTap: () => _addProductToCart(p, qty: 1),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _cart.isEmpty
          ? null
          : Material(
              elevation: 8,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_cart.length} líneas · $_cartUnits unidades',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              'Cobro y FX en P3',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) => ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                Text(
                                  'Ticket',
                                  style: Theme.of(ctx).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                ..._cart.map(
                                  (l) => ListTile(
                                    title: Text(l.name),
                                    subtitle: Text(
                                      '${l.unitPrice} ${l.currency} × ${l.quantity}',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Ver ticket'),
                      ),
                      FilledButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Confirmar venta (POST /sales) llega en P3.',
                              ),
                            ),
                          );
                        },
                        child: const Text('Cobrar'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
