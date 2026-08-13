import 'package:flutter/material.dart';

import '../../core/api/purchases_api.dart';
import '../../core/models/purchase.dart';
import '../../core/models/purchase_void.dart';
import '../sale/pos_sale_ui_tokens.dart';

/// Sheet de anulación: preview mock + motivo. **No llama al backend** mientras
/// [PurchasesApi.purchaseVoidRemoteEnabled] sea false.
Future<void> showPurchaseVoidSheet({
  required BuildContext context,
  required PurchaseDetail detail,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PurchaseVoidSheet(detail: detail),
  );
}

class _PurchaseVoidSheet extends StatefulWidget {
  const _PurchaseVoidSheet({required this.detail});

  final PurchaseDetail detail;

  @override
  State<_PurchaseVoidSheet> createState() => _PurchaseVoidSheetState();
}

class _PurchaseVoidSheetState extends State<_PurchaseVoidSheet> {
  late final PurchaseVoidPreview _preview;
  late final TextEditingController _reason;
  bool _confirmPartial = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _preview = PurchaseVoidMock.fromDetail(widget.detail);
    _reason = TextEditingController();
    _confirmPartial = !_preview.hasPartialStockSkip;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _onConfirmUiOnly() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _formError = 'Indicá el motivo de anulación.');
      return;
    }
    if (reason.length > 240) {
      setState(() => _formError = 'Motivo: máximo 240 caracteres.');
      return;
    }
    if (_preview.hasPartialStockSkip && !_confirmPartial) {
      setState(
        () => _formError =
            'Confirmá que entendés que parte del stock no se revertirá.',
      );
      return;
    }
    // No llamar PurchasesApi.voidPurchase mientras el flag esté en false.
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 6),
        content: Text(
          'Anulación preparada en UI (preview mock). '
          'El servidor no se modificó: falta conectar el API void.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Material(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: PosSaleUi.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Anular factura',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3A2F1A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    PurchasesApi.purchaseVoidRemoteEnabled
                        ? 'API void habilitado en cliente.'
                        : 'Pendiente de API — preview MOCK. '
                            'No se anula en el servidor todavía.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orangeAccent,
                          height: 1.35,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Impacto estimado',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                _kv(
                  'Saldo (deuda)',
                  '${_preview.debt.amountDueFunctionalBefore ?? '—'} → '
                  '${_preview.debt.amountDueFunctionalAfter ?? '0'}',
                ),
                _kv(
                  'Abonos',
                  _preview.payments.willReversePayments
                      ? 'Se revertirán (${_preview.payments.amountPaidFunctional ?? '—'})'
                      : 'Sin abonos a revertir',
                ),
                const SizedBox(height: 14),
                Text(
                  'Líneas / stock',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                ..._preview.lines.map(
                  (l) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(l.productName ?? l.productId),
                      subtitle: Text(
                        'Comprado ${l.quantityPurchased} · '
                        'Revertible ${l.quantityReversible} · '
                        'Omitido ${l.quantitySkipped}'
                        '${l.skipReason == null ? '' : '\n${l.skipReason}'}',
                      ),
                      isThreeLine: l.skipReason != null,
                    ),
                  ),
                ),
                if (_preview.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._preview.warnings.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            size: 18,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              w,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (_preview.hasPartialStockSkip) ...[
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _confirmPartial,
                    onChanged: (v) =>
                        setState(() => _confirmPartial = v ?? false),
                    title: const Text(
                      'Entiendo que parte del stock no se revertirá '
                      '(posible venta).',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  maxLength: 240,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Motivo de anulación',
                    hintText: 'Ej. Factura duplicada / error de carga',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_formError != null) ...[
                  Text(
                    _formError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: _onConfirmUiOnly,
                  child: const Text('Confirmar (solo UI)'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(color: PosSaleUi.textMuted)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
