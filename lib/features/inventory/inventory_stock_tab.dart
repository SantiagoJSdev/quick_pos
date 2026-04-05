import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/models/inventory_line.dart';
import 'inventory_product_detail_screen.dart';

/// B1 — contenido de **Stock** (sin `Scaffold`; va dentro de [InventoryModuleScreen]).
class InventoryStockTab extends StatefulWidget {
  const InventoryStockTab({
    super.key,
    required this.storeId,
    required this.inventoryApi,
    this.onLoadedCount,
  });

  final String storeId;
  final InventoryApi inventoryApi;

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
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre, SKU o pegar código de barras',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Text(
            'Búsqueda por teclado. Escanear con cámara quedará en Venta (Sprint 2). '
            'Para dar de alta productos usá la pestaña Catálogo.',
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
