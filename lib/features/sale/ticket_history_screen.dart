import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/sales_api.dart';
import '../../core/models/recent_sale_ticket.dart';
import '../../core/storage/local_prefs.dart';
import 'pos_sale_ui_tokens.dart';

/// Tickets guardados en este dispositivo + detalle remoto `GET /sales/:id` si hay red.
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

class _TicketHistoryScreenState extends State<TicketHistoryScreen> {
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
              future: widget.salesApi.getSale(widget.storeId, t.saleId),
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
                          'ID: ${t.saleId}\n'
                          'Total local: ${t.totalDocument} ${t.documentCurrencyCode}',
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
                final pretty = const JsonEncoder.withIndent('  ').convert(json);
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
                              'Ticket ${t.saleId.substring(0, 8)}…',
                              style: const TextStyle(
                                color: PosSaleUi.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: t.saleId));
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
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: PosSaleUi.bg,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          backgroundColor: PosSaleUi.surface,
          foregroundColor: PosSaleUi.text,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Historial de tickets'),
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: PosSaleUi.primary),
              )
            : RefreshIndicator(
                color: PosSaleUi.primary,
                onRefresh: _load,
                child: _items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          Icon(Icons.receipt_long_outlined,
                              size: 56, color: PosSaleUi.textFaint),
                          SizedBox(height: 16),
                          Text(
                            'Todavía no hay tickets en este dispositivo',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: PosSaleUi.textMuted),
                          ),
                          SizedBox(height: 8),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Al cobrar en POS se guardan aquí. '
                              'Los enviados offline aparecen como “pendiente” hasta el sync.',
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
                          final queued =
                              t.status == RecentSaleTicket.statusQueued;
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
                            onTap: () => _openDetail(t),
                          );
                        },
                      ),
              ),
      ),
    );
  }
}
