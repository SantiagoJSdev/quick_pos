import 'package:flutter/material.dart';

import '../../core/models/held_ticket.dart';
import 'pos_sale_ui_tokens.dart';

/// Modal para guardar ticket en espera (alias / nota opcionales).
///
/// Los [TextEditingController] viven en un [StatefulWidget] y se disponen en
/// [State.dispose] **después** de desmontar el sheet — evita crash al cerrar
/// (no disponer mientras el [TextField] sigue montado en la animación de pop).
Future<void> showPosSaveHeldTicketSheet(
  BuildContext context, {
  required Future<void> Function(String? alias, String? note) onConfirm,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SaveHeldTicketSheetBody(onConfirm: onConfirm),
  );
}

class _SaveHeldTicketSheetBody extends StatefulWidget {
  const _SaveHeldTicketSheetBody({required this.onConfirm});

  final Future<void> Function(String? alias, String? note) onConfirm;

  @override
  State<_SaveHeldTicketSheetBody> createState() =>
      _SaveHeldTicketSheetBodyState();
}

class _SaveHeldTicketSheetBodyState extends State<_SaveHeldTicketSheetBody> {
  late final TextEditingController _aliasCtrl;
  late final TextEditingController _noteCtrl;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _aliasCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _aliasCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    final a = _aliasCtrl.text.trim();
    final n = _noteCtrl.text.trim();
    try {
      await widget.onConfirm(
        a.isEmpty ? null : a,
        n.isEmpty ? null : n,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo guardar el ticket: $e',
              maxLines: 3,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: Container(
        margin: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: PosSaleUi.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PosSaleUi.border),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: PosSaleUi.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Guardar ticket en espera',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: PosSaleUi.text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Guardá este ticket para retomarlo luego sin cobrarlo ahora. '
                'No se descuenta stock ni se registra venta hasta que cobres.',
                style: TextStyle(
                  fontSize: 13,
                  color: PosSaleUi.textMuted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _aliasCtrl,
                style: const TextStyle(color: PosSaleUi.text),
                decoration: const InputDecoration(
                  labelText: 'Alias (opcional)',
                  hintText: 'Ej. Cliente camisa azul',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: PosSaleUi.surface3,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                style: const TextStyle(color: PosSaleUi.text),
                decoration: const InputDecoration(
                  labelText: 'Nota (opcional)',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: PosSaleUi.surface3,
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: PosSaleUi.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Guardar en espera'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text(
                  'Cancelar',
                  style: TextStyle(color: PosSaleUi.textMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum RecoverCartConflictChoice {
  replace,
  saveCurrentAndOpen,
  cancel,
}

Future<RecoverCartConflictChoice?> showRecoverCartConflictDialog(
  BuildContext context,
) {
  return showDialog<RecoverCartConflictChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Carrito con productos'),
      content: const Text(
        'Ya tenés ítems en el ticket. ¿Qué querés hacer con el ticket en espera que elegiste?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, RecoverCartConflictChoice.cancel),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, RecoverCartConflictChoice.saveCurrentAndOpen),
          child: const Text('Guardar actual y abrir este'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(ctx, RecoverCartConflictChoice.replace),
          child: const Text('Reemplazar'),
        ),
      ],
    ),
  );
}

/// Lista de tickets en espera (bottom sheet).
Future<void> showPosHeldTicketsListSheet(
  BuildContext context, {
  required List<HeldTicket> tickets,
  required Future<List<HeldTicket>> Function() reloadTickets,
  required void Function(HeldTicket t) onRecover,
  required Future<void> Function(HeldTicket t) onRename,
  required Future<void> Function(HeldTicket t) onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _HeldTicketsListSheet(
      initialTickets: tickets,
      reloadTickets: reloadTickets,
      onRecover: onRecover,
      onRename: onRename,
      onDelete: onDelete,
    ),
  );
}

class _HeldTicketsListSheet extends StatefulWidget {
  const _HeldTicketsListSheet({
    required this.initialTickets,
    required this.reloadTickets,
    required this.onRecover,
    required this.onRename,
    required this.onDelete,
  });

  final List<HeldTicket> initialTickets;
  final Future<List<HeldTicket>> Function() reloadTickets;
  final void Function(HeldTicket t) onRecover;
  final Future<void> Function(HeldTicket t) onRename;
  final Future<void> Function(HeldTicket t) onDelete;

  @override
  State<_HeldTicketsListSheet> createState() => _HeldTicketsListSheetState();
}

class _HeldTicketsListSheetState extends State<_HeldTicketsListSheet> {
  late List<HeldTicket> _items;

  @override
  void initState() {
    super.initState();
    _items = List<HeldTicket>.from(widget.initialTickets);
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * 0.55;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: const BoxDecoration(
        color: PosSaleUi.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: PosSaleUi.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: PosSaleUi.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tickets en espera',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: PosSaleUi.text,
                ),
              ),
            ),
          ),
          if (_items.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottom),
              child: const Text(
                'No hay tickets guardados en este dispositivo.',
                style: TextStyle(color: PosSaleUi.textMuted),
              ),
            )
          else
            SizedBox(
              height: h,
              child: ListView.separated(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const Divider(
                  height: 1,
                  color: PosSaleUi.divider,
                ),
                itemBuilder: (c, i) {
                  final t = _items[i];
                  final timeShort = t.updatedAtIso.length >= 16
                      ? t.updatedAtIso.substring(0, 16).replaceFirst('T', ' ')
                      : t.updatedAtIso;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 4,
                      horizontal: 4,
                    ),
                    title: Text(
                      t.displayTitle,
                      style: const TextStyle(
                        color: PosSaleUi.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '$timeShort · ${t.lineCount} ítems · '
                      '${t.totalDocument} ${t.documentCurrencyCode}',
                      style: const TextStyle(
                        color: PosSaleUi.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Renombrar',
                          onPressed: () async {
                            await widget.onRename(t);
                            if (!mounted) return;
                            final next = await widget.reloadTickets();
                            if (mounted) {
                              setState(() => _items = next);
                            }
                          },
                          icon: const Icon(Icons.edit_outlined,
                              color: PosSaleUi.textMuted, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Eliminar',
                          onPressed: () async {
                            await widget.onDelete(t);
                            if (!mounted) return;
                            final next = await widget.reloadTickets();
                            if (mounted) setState(() => _items = next);
                          },
                          icon: const Icon(Icons.delete_outline,
                              color: PosSaleUi.error, size: 22),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onRecover(t);
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: PosSaleUi.primaryDim,
                            foregroundColor: PosSaleUi.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: const Text('Recuperar'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

Future<String?> showRenameHeldTicketDialog(
  BuildContext context, {
  required String currentAlias,
}) async {
  final ctrl = TextEditingController(text: currentAlias);
  try {
    return await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renombrar ticket'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Alias',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  } finally {
    ctrl.dispose();
  }
}
