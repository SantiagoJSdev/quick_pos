import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/models/inventory_line.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/models/stock_movement.dart';
import 'inventory_adjustment_screen.dart';

/// B2 — detalle de stock + movimientos recientes.
class InventoryProductDetailScreen extends StatefulWidget {
  const InventoryProductDetailScreen({
    super.key,
    required this.storeId,
    required this.inventoryApi,
    required this.localPrefs,
    required this.catalogInvalidationBus,
    required this.initialLine,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final LocalPrefs localPrefs;
  final CatalogInvalidationBus catalogInvalidationBus;
  final InventoryLine initialLine;

  String get _productId {
    final fromLine = initialLine.productId.trim();
    if (fromLine.isNotEmpty) return fromLine;
    return initialLine.product?.id.trim() ?? '';
  }

  @override
  State<InventoryProductDetailScreen> createState() =>
      _InventoryProductDetailScreenState();
}

class _InventoryProductDetailScreenState
    extends State<InventoryProductDetailScreen> {
  InventoryLine? _line;
  List<StockMovement> _movements = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _line = widget.initialLine;
    widget.catalogInvalidationBus.addListener(_onCatalogInvalidated);
    _load();
  }

  void _onCatalogInvalidated() {
    if (mounted) unawaited(_load());
  }

  @override
  void dispose() {
    widget.catalogInvalidationBus.removeListener(_onCatalogInvalidated);
    super.dispose();
  }

  Future<void> _load() async {
    final pid = widget._productId;
    if (pid.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Falta productId en la línea de inventario.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detailFuture = widget.inventoryApi.getInventoryLine(
        widget.storeId,
        pid,
      );
      final movFuture = widget.inventoryApi.listMovements(
        widget.storeId,
        productId: pid,
        limit: 100,
      );
      final detail = await detailFuture;
      final mov = await movFuture;
      if (!mounted) return;
      setState(() {
        _line = detail ?? widget.initialLine;
        _movements = mov;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      var msg = e.userMessage;
      if (e.requestId != null) msg = '$msg\n(requestId: ${e.requestId})';
      setState(() {
        _error = msg;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openAdjustment(String productId, String label) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => InventoryAdjustmentScreen(
          storeId: widget.storeId,
          inventoryApi: widget.inventoryApi,
          localPrefs: widget.localPrefs,
          productId: productId,
          productLabel: label,
        ),
      ),
    );
    if (ok == true && mounted) await _load();
  }

  String _formatWhen(DateTime? t) {
    if (t == null) return '—';
    final l = t.toLocal();
    final d =
        '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
    final h =
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    return '$d $h';
  }

  @override
  Widget build(BuildContext context) {
    final line = _line ?? widget.initialLine;
    final title = line.displayName;

    final pid = widget._productId;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (pid.isNotEmpty && !_loading && _error == null)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Ajustar stock',
              onPressed: () => _openAdjustment(pid, line.displayName),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _error == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null
                ? ListView(
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
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      Text(
                        'Stock',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _kv('Disponible', line.quantity),
                              _kv('Reservado', line.reserved),
                              if (line.averageUnitCostFunctional != null &&
                                  line.averageUnitCostFunctional!.isNotEmpty)
                                _kv(
                                  'Costo medio (func.)',
                                  line.averageUnitCostFunctional!,
                                ),
                              if (line.totalCostFunctional != null &&
                                  line.totalCostFunctional!.isNotEmpty)
                                _kv(
                                  'Valor stock (func.)',
                                  line.totalCostFunctional!,
                                ),
                              _kv('SKU', line.displaySku),
                              if (line.product?.barcode != null &&
                                  line.product!.barcode!.isNotEmpty)
                                _kv('Código de barras', line.product!.barcode!),
                            ],
                          ),
                        ),
                      ),
                      if (pid.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        FilledButton.tonalIcon(
                          onPressed: () => _openAdjustment(pid, line.displayName),
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: const Text('Ajustar stock'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Movimientos recientes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Últimos movimientos del producto (hasta 100).',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 12),
                      if (_movements.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              'Sin movimientos registrados.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        )
                      else
                        ..._movements.map(
                          (m) => Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(m.type),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatWhen(m.createdAt) +
                                        (m.reason != null &&
                                                m.reason!.isNotEmpty
                                            ? ' · ${m.reason}'
                                            : ''),
                                  ),
                                  if (m.referenceId != null &&
                                      m.referenceId!.isNotEmpty)
                                    Text(
                                      'Ref: ${m.referenceId}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  if (m.priceAtMoment != null &&
                                      m.priceAtMoment!.isNotEmpty)
                                    Text(
                                      'Precio (momento): ${m.priceAtMoment}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                m.quantity,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
