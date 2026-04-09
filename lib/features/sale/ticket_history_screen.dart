import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/sales_api.dart';
import '../../core/models/recent_sale_ticket.dart';
import '../../core/models/sales_list_page.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/widgets/quickmarket_branding.dart';
import 'pos_sale_ui_tokens.dart';

String _ticketShortNumberLabel(String? displayCode) {
  if (displayCode == null || displayCode.isEmpty) return '';
  final n = int.tryParse(displayCode.trim());
  return n != null ? '#$n' : '#$displayCode';
}

Future<String> _queuedSaleLinesSummary(
  LocalPrefs prefs,
  String storeId,
  String clientSaleId,
) async {
  final pending = await prefs.loadPendingSales();
  for (final e in pending) {
    if (e.storeId != storeId) continue;
    if ('${e.sale['id']}' != clientSaleId) continue;
    final raw = e.sale['lines'];
    if (raw is! List || raw.isEmpty) {
      return 'Sin líneas en la copia local.';
    }
    final buf = StringBuffer();
    var i = 0;
    for (final x in raw) {
      if (x is! Map) continue;
      final m = Map<String, dynamic>.from(x);
      final pid = (m['productId']?.toString() ?? '').trim();
      final qty = m['quantity']?.toString() ?? '?';
      final price = m['price']?.toString() ?? '?';
      i++;
      final pidShort =
          pid.length > 8 ? '${pid.substring(0, 8)}…' : (pid.isEmpty ? '—' : pid);
      buf.writeln('$i. $qty u. × $price  ·  $pidShort');
    }
    if (buf.isEmpty) return 'Sin líneas legibles en la copia local.';
    return buf.toString().trim();
  }
  return 'Esta venta ya no está en la cola local (quizá se sincronizó). '
      'Deslizá hacia abajo para refrescar el historial.';
}

String? _jsonStringField(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

List<Widget> _saleTicketVisualWidgets(
  BuildContext context,
  Map<String, dynamic> sale,
  String prettyJson,
) {
  final lines = _humanLinesFromRemoteSaleJson(sale);
  final doc = _jsonStringField(sale, 'documentCurrencyCode');
  final total = _jsonStringField(sale, 'totalDocument') ??
      _jsonStringField(sale, 'documentTotal');
  final stat = _jsonStringField(sale, 'status');
  final created = _jsonStringField(sale, 'createdAt');
  final paid = _jsonStringField(sale, 'paidDocumentTotal');
  final change = _jsonStringField(sale, 'changeDocument');

  final payBlocks = <Widget>[];
  final pmRaw = sale['payments'];
  if (pmRaw is List) {
    var k = 0;
    for (final p in pmRaw) {
      if (p is! Map) continue;
      k++;
      final m = Map<String, dynamic>.from(p);
      final method = _jsonStringField(m, 'method') ?? 'Pago $k';
      final amt = _jsonStringField(m, 'amount');
      final cur = _jsonStringField(m, 'currencyCode');
      final right = [amt, cur].whereType<String>().join(' ');
      payBlocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  method,
                  style: const TextStyle(color: PosSaleUi.text, fontSize: 13),
                ),
              ),
              Expanded(
                child: Text(
                  right.isEmpty ? '—' : right,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  const muted = TextStyle(color: PosSaleUi.textMuted, fontSize: 13);
  const label = TextStyle(
    color: PosSaleUi.textMuted,
    fontWeight: FontWeight.w600,
    fontSize: 12,
  );

  return [
    if (created != null) ...[
      const Text('Fecha', style: label),
      const SizedBox(height: 4),
      Text(created, style: muted),
      const SizedBox(height: 14),
    ],
    if (stat != null) ...[
      const Text('Estado', style: label),
      const SizedBox(height: 4),
      Text(stat, style: muted),
      const SizedBox(height: 14),
    ],
    const Text('Total del ticket', style: label),
    const SizedBox(height: 4),
    Text(
      total != null && doc != null
          ? '$total $doc'
          : (total ?? '—'),
      style: const TextStyle(
        color: PosSaleUi.text,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    ),
    if (paid != null || change != null) ...[
      const SizedBox(height: 10),
      if (paid != null)
        Text(
          'Pagado: $paid${doc != null ? ' $doc' : ''}',
          style: muted,
        ),
      if (change != null)
        Text(
          'Vuelto: $change${doc != null ? ' $doc' : ''}',
          style: muted,
        ),
    ],
    const SizedBox(height: 16),
    const Text('Productos', style: label),
    const SizedBox(height: 8),
    if (lines.isEmpty)
      const Text('Sin detalle de líneas.', style: muted)
    else
      ...lines.map(
        (t) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: PosSaleUi.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: PosSaleUi.border),
            ),
            child: Text(
              t,
              style: const TextStyle(color: PosSaleUi.text, fontSize: 13),
            ),
          ),
        ),
      ),
    if (payBlocks.isNotEmpty) ...[
      const SizedBox(height: 12),
      const Text('Pagos', style: label),
      const SizedBox(height: 8),
      ...payBlocks,
    ],
    const SizedBox(height: 8),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          showDialog<void>(
            context: context,
            builder: (dCtx) => AlertDialog(
              backgroundColor: PosSaleUi.surface2,
              title: const Text(
                'Datos técnicos',
                style: TextStyle(color: PosSaleUi.text),
              ),
              content: SingleChildScrollView(
                child: SelectableText(
                  prettyJson,
                  style: const TextStyle(
                    color: PosSaleUi.textMuted,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.info_outline, size: 18, color: PosSaleUi.textMuted),
        label: const Text(
          'Ver datos técnicos (soporte)',
          style: TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
        ),
      ),
    ),
  ];
}

List<String> _humanLinesFromRemoteSaleJson(Map<String, dynamic> sale) {
  final raw = sale['saleLines'] ?? sale['lines'];
  if (raw is! List) return const [];
  final out = <String>[];
  var i = 0;
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    i++;
    var label = m['productId']?.toString() ?? '';
    final prod = m['product'];
    if (prod is Map) {
      final name = prod['name']?.toString();
      final sku = prod['sku']?.toString();
      if (name != null && name.isNotEmpty) label = name;
      if (sku != null && sku.isNotEmpty) {
        label = label.isEmpty ? sku : '$label · $sku';
      }
    }
    if (label.isEmpty) label = 'Producto';
    final qty = m['quantity']?.toString() ?? '?';
    final price = m['price']?.toString();
    final lineTotal = m['lineTotalDocument']?.toString();
    final extra = lineTotal != null && lineTotal.isNotEmpty
        ? ' → $lineTotal'
        : (price != null ? ' @ $price' : '');
    out.add('$i. $label  ·  $qty u.$extra');
  }
  return out;
}

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _saleRowTitle(SalesListItem it) {
  final doc = it.totalDocument;
  final cur = it.documentCurrencyCode ?? '';
  if (doc != null && doc.isNotEmpty) {
    return cur.isNotEmpty ? '$doc $cur' : doc;
  }
  final tf = it.totalFunctional;
  if (tf != null && tf.isNotEmpty) return '$tf (func.)';
  return '—';
}

/// Pestaña **Este dispositivo**: ventas locales del día actual. **General**: `GET /sales` (backend).
class TicketHistoryScreen extends StatefulWidget {
  const TicketHistoryScreen({
    super.key,
    required this.storeId,
    required this.localPrefs,
    required this.salesApi,
  });

  final String storeId;
  final LocalPrefs localPrefs;
  final SalesApi salesApi;

  @override
  State<TicketHistoryScreen> createState() => _TicketHistoryScreenState();
}

class _TicketHistoryScreenState extends State<TicketHistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openDetail(RecentSaleTicket t) async {
    if (t.status == RecentSaleTicket.statusQueued) {
      if (!mounted) return;
      final lines =
          await _queuedSaleLinesSummary(widget.localPrefs, widget.storeId, t.saleId);
      if (!mounted) return;
      final noLabel = _ticketShortNumberLabel(t.displayCode);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: PosSaleUi.surface2,
          title: Text(
            noLabel.isEmpty ? 'Venta en cola' : 'Venta en cola $noLabel',
            style: const TextStyle(color: PosSaleUi.text),
          ),
          content: SingleChildScrollView(
            child: Text(
              'Se enviará sola al reconectar (sync en segundo plano al abrir la app '
              'o cada ~90 s). No hace falta un botón de envío manual.\n\n'
              'Total: ${t.totalDocument} ${t.documentCurrencyCode}\n'
              '${noLabel.isNotEmpty ? 'Nº ticket: ${noLabel.replaceFirst('#', '')}\n' : ''}'
              '\nProductos (copia local):\n$lines\n\n'
              'ID interno (soporte):\n${t.saleId}',
              style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
            if (noLabel.isNotEmpty)
              FilledButton(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: noLabel.replaceFirst('#', '')),
                  );
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Número de ticket copiado')),
                  );
                },
                child: Text('Copiar $noLabel'),
              )
            else
              FilledButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: t.saleId));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID copiado')),
                  );
                },
                child: const Text('Copiar ID'),
              ),
          ],
        ),
      );
      return;
    }

    if (!mounted) return;
    final titleBit = (t.displayCode != null && t.displayCode!.isNotEmpty)
        ? _ticketShortNumberLabel(t.displayCode)
        : t.saleId;
    await _openRemoteSaleBottomSheet(
      context,
      widget.salesApi,
      widget.storeId,
      t.saleId,
      titleSuffix: titleBit,
      fallbackTotal: t.totalDocument,
      fallbackCurrency: t.documentCurrencyCode,
    );
  }

  Future<void> _openRemoteSaleBottomSheet(
    BuildContext context,
    SalesApi api,
    String storeId,
    String saleId, {
    required String titleSuffix,
    String? fallbackTotal,
    String? fallbackCurrency,
  }) async {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PosSaleUi.surface,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return FutureBuilder<Map<String, dynamic>>(
              future: api.getSale(storeId, saleId),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: CircularProgressIndicator(color: PosSaleUi.primary),
                    ),
                  );
                }
                if (snap.hasError) {
                  final err = snap.error;
                  final msg = err is ApiError
                      ? err.userMessageForSupport
                      : err.toString();
                  return Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'No se pudo cargar el detalle',
                          style: TextStyle(
                            color: PosSaleUi.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          msg,
                          style: const TextStyle(color: PosSaleUi.textMuted),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'ID: $saleId\n'
                          'Total local: ${fallbackTotal ?? '—'} ${fallbackCurrency ?? ''}',
                          style: const TextStyle(
                            color: PosSaleUi.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                final json = snap.data!;
                final pretty =
                    const JsonEncoder.withIndent('  ').convert(json);
                final headerTitle = titleSuffix.startsWith('#')
                    ? 'Ticket $titleSuffix'
                    : (titleSuffix.length > 14
                        ? '${titleSuffix.substring(0, 14)}…'
                        : titleSuffix);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: PosSaleUi.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              headerTitle,
                              style: const TextStyle(
                                color: PosSaleUi.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copiar UUID servidor',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: saleId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('UUID de venta copiado')),
                              );
                            },
                            icon: const Icon(Icons.copy,
                                color: PosSaleUi.textMuted),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _saleTicketVisualWidgets(
                            context,
                            json,
                            pretty,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const QuickMarketLogoMark(size: 26, borderRadius: 8),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Historial de tickets',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: PosSaleUi.text,
                      fontWeight: FontWeight.w600,
                    ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: PosSaleUi.primary,
          labelColor: PosSaleUi.text,
          unselectedLabelColor: PosSaleUi.textMuted,
          tabs: const [
            Tab(text: 'Este dispositivo'),
            Tab(text: 'General'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DeviceHistoryTab(
            storeId: widget.storeId,
            localPrefs: widget.localPrefs,
            salesApi: widget.salesApi,
            onOpenDetail: _openDetail,
          ),
          _GeneralHistoryTab(
            storeId: widget.storeId,
            localPrefs: widget.localPrefs,
            salesApi: widget.salesApi,
            onOpenRemote: (saleId, total, currency) => _openRemoteSaleBottomSheet(
                  context,
                  widget.salesApi,
                  widget.storeId,
                  saleId,
                  titleSuffix: saleId,
                  fallbackTotal: total,
                  fallbackCurrency: currency,
                ),
          ),
        ],
      ),
    );
  }
}

class _DeviceHistoryTab extends StatefulWidget {
  const _DeviceHistoryTab({
    required this.storeId,
    required this.localPrefs,
    required this.salesApi,
    required this.onOpenDetail,
  });

  final String storeId;
  final LocalPrefs localPrefs;
  final SalesApi salesApi;
  final void Function(RecentSaleTicket t) onOpenDetail;

  @override
  State<_DeviceHistoryTab> createState() => _DeviceHistoryTabState();
}

class _DeviceHistoryTabState extends State<_DeviceHistoryTab> {
  List<RecentSaleTicket> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await widget.localPrefs
        .reconcileRecentQueuedTicketsWithPendingSales(widget.storeId);
    var all = await widget.localPrefs.loadRecentSaleTickets();
    var forStore =
        all.where((e) => e.storeId == widget.storeId).toList(growable: false);
    for (final t in forStore) {
      if (t.status != RecentSaleTicket.statusQueued) continue;
      try {
        await widget.salesApi.getSale(widget.storeId, t.saleId);
        await widget.localPrefs.markRecentSaleTicketSyncedByClientId(t.saleId);
      } catch (_) {}
    }
    all = await widget.localPrefs.loadRecentSaleTickets();
    forStore =
        all.where((e) => e.storeId == widget.storeId).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _items = forStore;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: PosSaleUi.primary),
      );
    }
    return RefreshIndicator(
      color: PosSaleUi.primary,
      onRefresh: _load,
      child: _items.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 80),
                Icon(Icons.smartphone_outlined,
                    size: 56, color: PosSaleUi.textFaint),
                SizedBox(height: 16),
                Text(
                  'No hay ventas de hoy en este dispositivo',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PosSaleUi.textMuted),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Solo se guarda localmente el día calendario actual; al cambiar de día se limpia. '
                    'Para otras fechas usá la pestaña General.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: PosSaleUi.textFaint,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _items.length,
              separatorBuilder: (context, i) => const Divider(
                height: 1,
                color: PosSaleUi.divider,
              ),
              itemBuilder: (context, i) {
                final t = _items[i];
                final queued = t.status == RecentSaleTicket.statusQueued;
                final dt = DateTime.tryParse(t.recordedAtIso);
                final sub = dt != null
                    ? '${dt.toLocal().toString().substring(0, 19)} · '
                        '${queued ? "Pendiente envío (sync auto.)" : "En servidor"}'
                    : t.status;
                final no = _ticketShortNumberLabel(t.displayCode);
                return ListTile(
                  title: Text(
                    no.isEmpty
                        ? '${t.totalDocument} ${t.documentCurrencyCode}'
                        : '$no · ${t.totalDocument} ${t.documentCurrencyCode}',
                    style: const TextStyle(
                      color: PosSaleUi.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    sub,
                    style: const TextStyle(
                      color: PosSaleUi.textMuted,
                      fontSize: 12,
                    ),
                  ),
                  trailing: Icon(
                    queued ? Icons.cloud_queue : Icons.chevron_right,
                    color: PosSaleUi.textMuted,
                  ),
                  onTap: () => widget.onOpenDetail(t),
                );
              },
            ),
    );
  }
}

class _GeneralHistoryTab extends StatefulWidget {
  const _GeneralHistoryTab({
    required this.storeId,
    required this.localPrefs,
    required this.salesApi,
    required this.onOpenRemote,
  });

  final String storeId;
  final LocalPrefs localPrefs;
  final SalesApi salesApi;
  final Future<void> Function(String saleId, String? total, String? currency)
      onOpenRemote;

  @override
  State<_GeneralHistoryTab> createState() => _GeneralHistoryTabState();
}

class _GeneralHistoryTabState extends State<_GeneralHistoryTab> {
  late DateTime _from;
  late DateTime _to;
  bool _onlyThisDevice = false;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  List<SalesListItem> _rows = [];
  String? _nextCursor;
  SalesListMeta? _meta;
  bool _hasFetched = false;
  String? _deviceId;
  bool _usingCachedData = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = DateTime(n.year, n.month, n.day);
    _to = _from;
    _primeDeviceId();
  }

  Future<void> _primeDeviceId() async {
    final id = await widget.localPrefs.getOrCreateDeviceId();
    if (mounted) setState(() => _deviceId = id);
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _to = picked);
  }

  Future<void> _fetch({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextCursor = null;
      });
    } else {
      if (_nextCursor == null || _nextCursor!.isEmpty || _loadingMore) return;
      setState(() => _loadingMore = true);
    }
    try {
      final from = DateTime(_from.year, _from.month, _from.day);
      var to = DateTime(_to.year, _to.month, _to.day);
      if (to.isBefore(from)) {
        to = from;
        if (mounted) setState(() => _to = from);
      }
      final cursor = reset ? null : _nextCursor;
      final page = await widget.salesApi.listSales(
        widget.storeId,
        dateFrom: _ymd(from),
        dateTo: _ymd(to),
        deviceId: _onlyThisDevice ? _deviceId : null,
        limit: 50,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _rows = List<SalesListItem>.from(page.items);
        } else {
          _rows = [..._rows, ...page.items];
        }
        _nextCursor = page.nextCursor;
        _meta = page.meta;
        _loading = false;
        _loadingMore = false;
        _hasFetched = true;
        _error = null;
        _usingCachedData = false;
      });
      if (reset) {
        await widget.localPrefs.saveSalesGeneralCache(
          widget.storeId,
          rows: page.items,
          meta: page.meta,
          dateFrom: _ymd(from),
          dateTo: _ymd(to),
          onlyThisDevice: _onlyThisDevice,
        );
      }
    } catch (e) {
      if (reset) {
        final cached = await widget.localPrefs.loadSalesGeneralCache(widget.storeId);
        if (cached != null && cached.rows.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _rows = cached.rows;
            _meta = cached.meta;
            _nextCursor = null;
            _loading = false;
            _loadingMore = false;
            _hasFetched = true;
            _error = null;
            _usingCachedData = true;
            if (cached.dateFrom != null) {
              final p = DateTime.tryParse(cached.dateFrom!);
              if (p != null) _from = DateTime(p.year, p.month, p.day);
            }
            if (cached.dateTo != null) {
              final p = DateTime.tryParse(cached.dateTo!);
              if (p != null) _to = DateTime(p.year, p.month, p.day);
            }
            if (cached.onlyThisDevice != null) {
              _onlyThisDevice = cached.onlyThisDevice!;
            }
          });
          return;
        }
      }
      if (!mounted) return;
      String msg = e.toString();
      if (e is ApiError) {
        msg = e.userMessageForSupport;
        if (e.statusCode == 400) {
          msg =
              '$msg\n(Rango máximo 31 días; fechas en zona de la tienda — ver documentación.)';
        }
      }
      setState(() {
        _error = msg;
        if (reset) {
          _rows = [];
          _nextCursor = null;
          _meta = null;
          _hasFetched = false;
        }
        _loading = false;
        _loadingMore = false;
        _usingCachedData = false;
      });
    }
  }

  String _subtitle(SalesListItem it) {
    final buf = StringBuffer();
    final ca = it.createdAt;
    if (ca != null && ca.isNotEmpty) buf.write(ca);
    if (it.status != null && it.status!.isNotEmpty) {
      if (buf.isNotEmpty) buf.write(' · ');
      buf.write(it.status);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tz = _meta?.timezone;
    final range = _meta != null &&
            _meta!.dateFrom != null &&
            _meta!.dateTo != null
        ? '${_meta!.dateFrom} → ${_meta!.dateTo}'
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Consulta en el servidor. Las fechas son calendario de la tienda; '
          'sin fechas el backend usa últimos 7 días.',
          style: TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _pickFrom,
                child: Text('Desde ${_ymd(_from)}',
                    style: const TextStyle(color: PosSaleUi.text)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: _loading ? null : _pickTo,
                child: Text('Hasta ${_ymd(_to)}',
                    style: const TextStyle(color: PosSaleUi.text)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Solo este dispositivo',
              style: TextStyle(color: PosSaleUi.text, fontSize: 14)),
          subtitle: Text(
            _deviceId == null ? 'Cargando ID…' : _deviceId!,
            style: const TextStyle(color: PosSaleUi.textFaint, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          value: _onlyThisDevice,
          onChanged: _deviceId == null || _loading
              ? null
              : (v) => setState(() => _onlyThisDevice = v),
          activeThumbColor: PosSaleUi.primary,
        ),
        FilledButton(
          onPressed: _loading ? null : () => _fetch(reset: true),
          child: _loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Consultar'),
        ),
        if (tz != null && tz.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Zona tienda: $tz${range != null ? ' · Rango aplicado: $range' : ''}',
            style: const TextStyle(color: PosSaleUi.textFaint, fontSize: 11),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(
            _error!,
            style: const TextStyle(color: Colors.orangeAccent, fontSize: 13),
          ),
        ],
        if (_usingCachedData) ...[
          const SizedBox(height: 8),
          const Text(
            'Mostrando historial cacheado (modo offline).',
            style: TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ],
        const SizedBox(height: 16),
        if (!_loading && _error == null && _rows.isEmpty && !_hasFetched)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Tocá «Consultar» para cargar ventas del servidor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PosSaleUi.textFaint, fontSize: 13),
            ),
          ),
        if (!_loading && _error == null && _rows.isEmpty && _hasFetched)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No hay ventas en ese rango.',
              textAlign: TextAlign.center,
              style: TextStyle(color: PosSaleUi.textFaint, fontSize: 13),
            ),
          ),
        ..._rows.map((it) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _saleRowTitle(it),
              style: const TextStyle(
                color: PosSaleUi.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _subtitle(it),
              style: const TextStyle(
                color: PosSaleUi.textMuted,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right, color: PosSaleUi.textMuted),
            onTap: () => widget.onOpenRemote(
                  it.id,
                  it.totalDocument,
                  it.documentCurrencyCode,
                ),
          );
        }),
        if (_hasFetched &&
            _rows.isNotEmpty &&
            _nextCursor != null &&
            _nextCursor!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _loadingMore || _loading
                  ? null
                  : () => _fetch(reset: false),
              child: _loadingMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cargar más'),
            ),
          ),
        ],
      ],
    );
  }
}
