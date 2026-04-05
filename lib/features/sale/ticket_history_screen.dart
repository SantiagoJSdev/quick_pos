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
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: PosSaleUi.surface2,
          title: const Text('Venta en cola',
              style: TextStyle(color: PosSaleUi.text)),
          content: Text(
            'Este ticket aún no se envió al servidor (sin conexión al facturar).\n\n'
            'ID cliente: ${t.saleId}\n'
            'Total: ${t.totalDocument} ${t.documentCurrencyCode}\n\n'
            'Tras sincronizar, el servidor puede asignar o confirmar el mismo id.',
            style: const TextStyle(color: PosSaleUi.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
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
    await _openRemoteSaleBottomSheet(
      context,
      widget.salesApi,
      widget.storeId,
      t.saleId,
      titleSuffix: t.saleId,
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
                      ? err.userMessage
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
                              'Ticket ${titleSuffix.length > 8 ? '${titleSuffix.substring(0, 8)}…' : titleSuffix}',
                              style: const TextStyle(
                                color: PosSaleUi.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: saleId));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('ID copiado')),
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
                        child: SelectableText(
                          pretty,
                          style: const TextStyle(
                            color: PosSaleUi.textMuted,
                            fontSize: 11,
                            fontFamily: 'monospace',
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
    required this.onOpenDetail,
  });

  final String storeId;
  final LocalPrefs localPrefs;
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
    final all = await widget.localPrefs.loadRecentSaleTickets();
    final forStore =
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
                        '${queued ? "Pendiente envío" : "En servidor"}'
                    : t.status;
                return ListTile(
                  title: Text(
                    '${t.totalDocument} ${t.documentCurrencyCode}',
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
      });
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (e is ApiError) {
        msg = e.userMessage;
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
