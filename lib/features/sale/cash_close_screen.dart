import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/cash_sessions_api.dart';
import '../../core/api/sync_api.dart';
import '../../core/cash/cash_session_service.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/models/cash_session.dart';
import '../../core/pos/pos_terminal_info.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/sync_cycle.dart';
import '../shell/shell_online_scope.dart';
import 'pos_sale_ui_tokens.dart';

/// Flujo **Cerrar caja** (conteo efectivo + sync + resumen + confirmar).
class CashCloseScreen extends StatefulWidget {
  const CashCloseScreen({
    super.key,
    required this.storeId,
    required this.localPrefs,
    required this.cashSessionsApi,
    required this.syncApi,
    required this.catalogInvalidationBus,
  });

  final String storeId;
  final LocalPrefs localPrefs;
  final CashSessionsApi cashSessionsApi;
  final SyncApi syncApi;
  final CatalogInvalidationBus catalogInvalidationBus;

  @override
  State<CashCloseScreen> createState() => _CashCloseScreenState();
}

class _CashCloseScreenState extends State<CashCloseScreen> {
  final _countedCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late final CashSessionService _service;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  LocalCashSession? _session;
  LocalClosePreview? _preview;
  CashSessionSummaryResponse? _remoteSummary;
  String? _statusHint;

  @override
  void initState() {
    super.initState();
    _service = CashSessionService(
      prefs: widget.localPrefs,
      api: widget.cashSessionsApi,
    );
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _countedCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final online = ShellOnlineScope.of(context);
      final terminal = await PosTerminalInfo.load(widget.localPrefs);
      var session = await widget.localPrefs.loadLocalCashSession(
        storeId: widget.storeId,
        deviceId: terminal.deviceId,
      );

      if (session != null && session.needsTransmit) {
        if (online) {
          final ok = await _service.tryTransmitPendingClose(
            storeId: widget.storeId,
            online: true,
          );
          session = await widget.localPrefs.loadLocalCashSession(
            storeId: widget.storeId,
            deviceId: terminal.deviceId,
          );
          if (!mounted) return;
          setState(() {
            _session = session;
            _loading = false;
            _statusHint = ok
                ? 'Había un cierre pendiente: ya se envió al servidor.'
                : 'Hay un cierre pendiente de transmitir.';
          });
          return;
        }
        if (!mounted) return;
        setState(() {
          _session = session;
          _loading = false;
          _statusHint =
              'Caja ya cerrada · pendiente transmitir. Conectate y abrí de nuevo.';
        });
        return;
      }

      session = await _service.ensureOpenSession(
        storeId: widget.storeId,
        online: online,
      );

      if (session.needsTransmit) {
        if (!mounted) return;
        setState(() {
          _session = session;
          _loading = false;
          _statusHint =
              'No se puede abrir un turno nuevo: hay un cierre pendiente de enviar.';
        });
        return;
      }

      final preview = await _service.buildLocalPreview(
        storeId: widget.storeId,
        session: session,
      );

      CashSessionSummaryResponse? remote;
      if (online &&
          session.remoteId != null &&
          session.remoteId!.trim().isNotEmpty) {
        try {
          remote = await widget.cashSessionsApi.getSummary(
            widget.storeId,
            session.remoteId!,
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _session = session;
        _preview = preview;
        _remoteSummary = remote;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _syncThenRefresh() async {
    final online = ShellOnlineScope.of(context);
    if (!online) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin red: no se puede sincronizar ahora.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final t = await PosTerminalInfo.load(widget.localPrefs);
      await runSyncCycle(
        storeId: widget.storeId,
        prefs: widget.localPrefs,
        syncApi: widget.syncApi,
        deviceId: t.deviceId,
        appVersion: t.appVersion,
        catalogInvalidation: widget.catalogInvalidationBus,
        doPull: true,
        doFlush: true,
      );
      await widget.localPrefs.markLastSuccessfulSyncNow();
      await _bootstrap();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmClose() async {
    final session = _session;
    if (session == null || !session.isOpen) return;
    final counted = _countedCtrl.text.trim().replaceAll(',', '.');
    if (counted.isEmpty || double.tryParse(counted) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresá el efectivo contado (número).')),
      );
      return;
    }

    final online = ShellOnlineScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PosSaleUi.surface2,
        title: const Text(
          'Confirmar cierre de caja',
          style: TextStyle(color: PosSaleUi.text),
        ),
        content: Text(
          online
              ? 'Se sincronizará lo pendiente y se cerrará el turno.'
              : 'Sin red: el cierre quedará marcado como pendiente transmitir.',
          style: const TextStyle(color: PosSaleUi.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cerrar caja'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      if (online) {
        final t = await PosTerminalInfo.load(widget.localPrefs);
        await runSyncCycle(
          storeId: widget.storeId,
          prefs: widget.localPrefs,
          syncApi: widget.syncApi,
          deviceId: t.deviceId,
          appVersion: t.appVersion,
          catalogInvalidation: widget.catalogInvalidationBus,
          doPull: true,
          doFlush: true,
        );
        await widget.localPrefs.markLastSuccessfulSyncNow();
      }

      final result = await _service.closeSession(
        storeId: widget.storeId,
        online: online,
        countedCash: counted,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        preview: _preview,
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: PosSaleUi.surface2,
          title: Text(
            result.ok ? 'Caja cerrada' : 'No se pudo cerrar',
            style: const TextStyle(color: PosSaleUi.text),
          ),
          content: Text(
            result.message,
            style: const TextStyle(color: PosSaleUi.textMuted),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Listo'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cerrar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final online = ShellOnlineScope.of(context);
    final s = _session;
    final p = _preview;
    final remote = _remoteSummary?.summary;

    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: PosSaleUi.bg,
        brightness: Brightness.dark,
      ),
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: PosSaleUi.surface,
          foregroundColor: PosSaleUi.text,
          title: const Text('Cerrar caja'),
          actions: [
            IconButton(
              tooltip: 'Sincronizar y refrescar',
              onPressed: _busy || _loading ? null : _syncThenRefresh,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync),
            ),
          ],
        ),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(color: PosSaleUi.primary),
              )
            : _error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: PosSaleUi.text),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _bootstrap,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                children: [
                  Text(
                    online ? 'Estado: Online' : 'Estado: Offline',
                    style: TextStyle(
                      color: online ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_statusHint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _statusHint!,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _card(
                    title: 'Turno',
                    children: [
                      Text(
                        s == null
                            ? 'Sin sesión'
                            : s.isOpen
                            ? 'Abierto${s.remoteId != null ? ' · sync OK' : ' · local'}'
                            : s.needsTransmit
                            ? 'Cerrado · pendiente transmitir'
                            : 'Cerrado',
                        style: const TextStyle(color: PosSaleUi.text),
                      ),
                      if (s?.openedAtIso != null)
                        Text(
                          'Desde: ${s!.openedAtIso}',
                          style: const TextStyle(
                            color: PosSaleUi.textMuted,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _card(
                    title: 'Resumen del turno',
                    children: [
                      _kv('Tickets (local)', '${p?.ticketsCount ?? '—'}'),
                      _kv(
                        'Ventas approx. (local)',
                        p?.salesTotalDocumentApprox ?? '—',
                      ),
                      _kv(
                        'Pendientes en cola',
                        '${p?.pendingSalesCount ?? '—'}',
                      ),
                      _kv(
                        'SKUs con stock negativo',
                        '${remote?.negativeSkuCount ?? p?.negativeSkuCount ?? '—'}',
                      ),
                      if (remote != null) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Servidor',
                          style: TextStyle(
                            color: PosSaleUi.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        _kv('Tickets', '${remote.ticketsCount ?? '—'}'),
                        _kv(
                          'Neto funcional',
                          remote.netSalesFunctional ?? '—',
                        ),
                        _kv(
                          'Conflictos stock',
                          '${remote.stockConflictSalesCount ?? '—'}',
                        ),
                        _kv(
                          'Sync failed',
                          '${remote.syncFailedCount ?? '—'}',
                        ),
                      ],
                    ],
                  ),
                  if (s != null && s.isOpen) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _countedCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      style: const TextStyle(color: PosSaleUi.text),
                      decoration: const InputDecoration(
                        labelText: 'Efectivo contado',
                        labelStyle: TextStyle(color: PosSaleUi.textMuted),
                        hintText: '0.00',
                        filled: true,
                        fillColor: PosSaleUi.surface3,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _notesCtrl,
                      style: const TextStyle(color: PosSaleUi.text),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notas (opcional)',
                        labelStyle: TextStyle(color: PosSaleUi.textMuted),
                        filled: true,
                        fillColor: PosSaleUi.surface3,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _confirmClose,
                      icon: const Icon(Icons.lock_outline),
                      label: Text(
                        _busy ? 'Cerrando…' : 'Confirmar cierre de caja',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: PosSaleUi.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'El cierre no reemplaza el sync del día: fuerza un último '
                      'envío (si hay red) y congela el resumen del turno.',
                      style: TextStyle(
                        color: PosSaleUi.textFaint,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PosSaleUi.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosSaleUi.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: PosSaleUi.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 13),
            ),
          ),
          Text(
            v,
            style: const TextStyle(
              color: PosSaleUi.text,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
