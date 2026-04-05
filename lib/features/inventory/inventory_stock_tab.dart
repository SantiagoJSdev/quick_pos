import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/api/products_api.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/models/inventory_line.dart';
import '../sale/barcode_scanner_screen.dart';
import 'inventory_product_detail_screen.dart';
import 'product_form_screen.dart';

/// B1 — contenido de **Stock** (sin `Scaffold`; va dentro de [InventoryModuleScreen]).
class InventoryStockTab extends StatefulWidget {
  const InventoryStockTab({
    super.key,
    required this.storeId,
    required this.inventoryApi,
    required this.productsApi,
    required this.localPrefs,
    this.onLoadedCount,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final ProductsApi productsApi;
  final LocalPrefs localPrefs;

  /// Total de líneas tras cada carga (para contador en el módulo).
  final ValueChanged<int>? onLoadedCount;

  @override
  State<InventoryStockTab> createState() => _InventoryStockTabState();
}

class _InventoryStockTabState extends State<InventoryStockTab> {
  final _searchController = TextEditingController();
  List<InventoryLine> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _load();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.inventoryApi.listInventory(widget.storeId);
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
      widget.onLoadedCount?.call(_all.length);
    } on ApiError catch (e) {
      if (!mounted) return;
      var msg = e.userMessage;
      if (e.requestId != null) msg = '$msg\n(requestId: ${e.requestId})';
      setState(() {
        _all = [];
        _error = msg;
        _loading = false;
      });
      widget.onLoadedCount?.call(0);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _all = [];
        _error = e.toString();
        _loading = false;
      });
      widget.onLoadedCount?.call(0);
    }
  }

  bool _anyLineExactBarcode(String raw) {
    final c = raw.trim().toLowerCase();
    if (c.isEmpty) return false;
    for (final line in _all) {
      final b = line.product?.barcode?.trim().toLowerCase();
      if (b != null && b.isNotEmpty && b == c) return true;
    }
    return false;
  }

  Future<void> _openNewProductWithBarcode(String code) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => ProductFormScreen(
          storeId: widget.storeId,
          productsApi: widget.productsApi,
          initialBarcode: code,
        ),
      ),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _onScanPressed() async {
    if (_loading) return;
    if (!BarcodeScannerScreen.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El escáner solo está disponible en Android e iOS.'),
        ),
      );
      return;
    }
    final code = await BarcodeScannerScreen.open(context);
    if (!mounted || code == null || code.isEmpty) return;
    setState(() => _searchController.text = code);
    if (!_anyLineExactBarcode(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No hay producto en stock con este código de barras.',
          ),
          action: SnackBarAction(
            label: 'Crear producto',
            onPressed: () => _openNewProductWithBarcode(code),
          ),
        ),
      );
    }
  }

  List<InventoryLine> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((line) {
      final name = line.product?.name?.toLowerCase() ?? '';
      final sku = line.product?.sku?.toLowerCase() ?? '';
      final bc = line.product?.barcode?.toLowerCase() ?? '';
      return name.contains(q) || sku.contains(q) || bc.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, SKU o código de barras',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear',
                onPressed: _loading ? null : _onScanPressed,
              ),
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Text(
            'Podés pegar o escanear el código: el filtro coincide con nombre, SKU y código de barras.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }
    final items = _filtered;
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.12),
          Center(
            child: Text(
              _all.isEmpty
                  ? 'No hay stock registrado aún.\n\n'
                      'Si recién creás la tienda, primero cargá productos en la pestaña '
                      'Catálogo (arriba) y luego registrá entradas desde el detalle de cada ítem.'
                  : 'Ningún resultado para la búsqueda.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final line = items[i];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          title: Text(line.displayName),
          subtitle: Text(
            'SKU: ${line.displaySku}'
            '${line.product?.barcode != null && line.product!.barcode!.isNotEmpty ? ' · ${line.product!.barcode}' : ''}',
          ),
          onTap: () {
            Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (ctx) => InventoryProductDetailScreen(
                  storeId: widget.storeId,
                  inventoryApi: widget.inventoryApi,
                  localPrefs: widget.localPrefs,
                  initialLine: line,
                ),
              ),
            );
          },
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                line.quantity,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'disp.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
