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

  @override
  Widget build(BuildContext context) {
    final filtered = _filterType == 'ALL'
        ? _rows
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
                                final dt = DateTime.tryParse(r.timestampIso)
                                    ?.toLocal()
                                    .toString();
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: PosSaleUi.surface2,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
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

