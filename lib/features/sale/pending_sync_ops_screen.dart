import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/storage/local_prefs.dart';
import 'pos_sale_ui_tokens.dart';

class PendingSyncOpsScreen extends StatefulWidget {
  const PendingSyncOpsScreen({
    super.key,
    required this.storeId,
    required this.localPrefs,
  });

  final String storeId;
  final LocalPrefs localPrefs;

  @override
  State<PendingSyncOpsScreen> createState() => _PendingSyncOpsScreenState();
}

class _PendingSyncOpsScreenState extends State<PendingSyncOpsScreen> {
  bool _loading = true;
  String? _error;
  List<_PendingOpRow> _rows = const [];
  String _filterType = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await widget.localPrefs.loadPendingSales();
      final adjusts = await widget.localPrefs.loadPendingInventoryAdjusts();
      final purchases = await widget.localPrefs.loadPendingPurchaseReceives();
      final returns = await widget.localPrefs.loadPendingSaleReturns();
      final suppliers = await widget.localPrefs.loadPendingSupplierMutations();
      final catalog = await widget.localPrefs.loadPendingCatalogMutations();

      final rows = <_PendingOpRow>[
        ...sales
            .where((e) => e.storeId == widget.storeId)
            .map(
              (e) => _PendingOpRow(
                opId: e.opId,
                opType: 'SALE',
                timestampIso: e.opTimestampIso,
              ),
            ),
        ...adjusts
            .where((e) => e.storeId == widget.storeId)
            .map(
              (e) => _PendingOpRow(
                opId: e.opId,
                opType: 'INVENTORY_ADJUST',
                timestampIso: e.opTimestampIso,
              ),
            ),
        ...purchases
            .where((e) => e.storeId == widget.storeId)
            .map(
              (e) => _PendingOpRow(
                opId: e.opId,
                opType: 'PURCHASE_RECEIVE',
                timestampIso: e.opTimestampIso,
              ),
            ),
        ...returns
            .where((e) => e.storeId == widget.storeId)
            .map(
              (e) => _PendingOpRow(
                opId: e.opId,
                opType: 'SALE_RETURN',
                timestampIso: e.opTimestampIso,
              ),
            ),
        ...suppliers
            .where((e) => e.storeId == widget.storeId)
            .map(
              (e) => _PendingOpRow(
                opId: e.opId,
                opType: e.opType,
                timestampIso: e.opTimestampIso,
              ),
            ),
        ...catalog
            .where((e) => e.storeId == widget.storeId)
            .map(
              (e) => _PendingOpRow(
                opId: e.opId,
                opType: e.type,
                timestampIso: e.createdAtIso,
              ),
            ),
      ];
      rows.sort((a, b) => a.timestampIso.compareTo(b.timestampIso));
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  Future<void> _confirmDiscard(_PendingOpRow row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PosSaleUi.surface,
        title: const Text(
          'Descartar operación',
          style: TextStyle(color: PosSaleUi.text),
        ),
        content: Text(
          'Se quitará de la cola local del dispositivo y dejará de reenviarse '
          'en sync/push.\n\n'
          'opId: ${row.opId}\n'
          'Tipo: ${row.opType}\n\n'
          'El historial en el servidor (SyncOperation / ops metrics) puede '
          'seguir existiendo para auditoría. Si el dato no se aplicó en el '
          'backend, corregilo manualmente o volvé a crear la operación.',
          style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final removed = await widget.localPrefs.removePendingSyncOpByOpId(row.opId);
    if (!mounted) return;
    if (!removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se encontró la operación en la cola.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Operación descartada de la cola local.')),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filterType == 'ALL'
        ? _rows
        : _filterType == 'SUPPLIER'
        ? _rows
              .where((r) => r.opType.startsWith('SUPPLIER_'))
              .toList(growable: false)
        : _filterType == 'CATALOG'
        ? _rows
              .where(
                (r) =>
                    r.opType == 'CREATE_PRODUCT' ||
                    r.opType == 'CREATE_PRODUCT_WITH_STOCK' ||
                    r.opType == 'UPDATE_PRODUCT' ||
                    r.opType == 'DEACTIVATE_PRODUCT',
              )
              .toList(growable: false)
        : _rows.where((r) => r.opType == _filterType).toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Operaciones pendientes'),
        backgroundColor: PosSaleUi.surface,
        foregroundColor: PosSaleUi.text,
      ),
      backgroundColor: PosSaleUi.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: PosSaleUi.text),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
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
                      children: const [
                        SizedBox(height: 80),
                        Icon(
                          Icons.cloud_done_outlined,
                          color: PosSaleUi.textFaint,
                          size: 54,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'No hay operaciones pendientes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: PosSaleUi.textMuted),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Todas'),
                              selected: _filterType == 'ALL',
                              onSelected: (_) =>
                                  setState(() => _filterType = 'ALL'),
                            ),
                            ChoiceChip(
                              label: const Text('SALE'),
                              selected: _filterType == 'SALE',
                              onSelected: (_) =>
                                  setState(() => _filterType = 'SALE'),
                            ),
                            ChoiceChip(
                              label: const Text('INVENTORY_ADJUST'),
                              selected: _filterType == 'INVENTORY_ADJUST',
                              onSelected: (_) => setState(
                                () => _filterType = 'INVENTORY_ADJUST',
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('PURCHASE_RECEIVE'),
                              selected: _filterType == 'PURCHASE_RECEIVE',
                              onSelected: (_) => setState(
                                () => _filterType = 'PURCHASE_RECEIVE',
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('SALE_RETURN'),
                              selected: _filterType == 'SALE_RETURN',
                              onSelected: (_) =>
                                  setState(() => _filterType = 'SALE_RETURN'),
                            ),
                            ChoiceChip(
                              label: const Text('SUPPLIER_*'),
                              selected: _filterType == 'SUPPLIER',
                              onSelected: (_) =>
                                  setState(() => _filterType = 'SUPPLIER'),
                            ),
                            ChoiceChip(
                              label: const Text('CATALOG_*'),
                              selected: _filterType == 'CATALOG',
                              onSelected: (_) =>
                                  setState(() => _filterType = 'CATALOG'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (filtered.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 26),
                            child: Text(
                              'Sin operaciones para este filtro.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: PosSaleUi.textMuted),
                            ),
                          )
                        else
                          ...filtered.map((r) {
                            final dt = DateTime.tryParse(
                              r.timestampIso,
                            )?.toLocal().toString();
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: PosSaleUi.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            r.opType,
                                            style: const TextStyle(
                                              color: PosSaleUi.text,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Copiar opId',
                                          onPressed: () {
                                            Clipboard.setData(
                                              ClipboardData(text: r.opId),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text('opId copiado'),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.copy,
                                            size: 18,
                                            color: PosSaleUi.textMuted,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Descartar de la cola',
                                          onPressed: () =>
                                              unawaited(_confirmDiscard(r)),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            size: 18,
                                            color: Colors.orangeAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'opId: ${r.opId}',
                                      style: const TextStyle(
                                        color: PosSaleUi.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Creada: ${dt ?? r.timestampIso}',
                                      style: const TextStyle(
                                        color: PosSaleUi.textFaint,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                      ],
                    ),
            ),
    );
  }
}

class _PendingOpRow {
  const _PendingOpRow({
    required this.opId,
    required this.opType,
    required this.timestampIso,
  });

  final String opId;
  final String opType;
  final String timestampIso;
}
