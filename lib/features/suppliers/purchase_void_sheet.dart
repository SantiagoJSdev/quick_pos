import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/purchases_api.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/purchase.dart';
import '../../core/models/purchase_void.dart';
import '../../core/network/network_errors.dart';
import '../sale/pos_sale_ui_tokens.dart';

/// Sheet de anulación real: `void-preview` → confirmar → `void` (`docs/PURCHASES.md`).
/// Devuelve `true` si el servidor anuló la factura.
Future<bool?> showPurchaseVoidSheet({
  required BuildContext context,
  required String storeId,
  required PurchasesApi purchasesApi,
  required PurchaseDetail detail,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _PurchaseVoidSheet(
      storeId: storeId,
      purchasesApi: purchasesApi,
      detail: detail,
    ),
  );
}

class _PurchaseVoidSheet extends StatefulWidget {
  const _PurchaseVoidSheet({
    required this.storeId,
    required this.purchasesApi,
    required this.detail,
  });

  final String storeId;
  final PurchasesApi purchasesApi;
  final PurchaseDetail detail;

  @override
  State<_PurchaseVoidSheet> createState() => _PurchaseVoidSheetState();
}

class _PurchaseVoidSheetState extends State<_PurchaseVoidSheet> {
  PurchaseVoidPreview? _preview;
  bool _loadingPreview = true;
  String? _previewError;
  late final TextEditingController _reason;
  bool _confirmPartial = false;
  String? _formError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _reason = TextEditingController();
    _loadPreview();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });
    try {
      final preview = await widget.purchasesApi.previewVoidPurchase(
        widget.storeId,
        widget.detail.summary.id,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loadingPreview = false;
        _confirmPartial = !preview.hasPartialStockSkip;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _previewError = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _previewError = isLikelyNetworkFailure(e)
            ? 'Sin conexión. La anulación requiere internet.'
            : e.toString();
      });
    }
  }

  Future<void> _onConfirm() async {
    final preview = _preview;
    if (preview == null) return;
    if (!preview.canVoid) {
      setState(
        () => _formError = preview.blockers.isEmpty
            ? 'No se puede anular esta factura.'
            : preview.blockers.join(', '),
      );
      return;
    }
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _formError = 'Indicá el motivo de anulación.');
      return;
    }
    if (reason.length > 240) {
      setState(() => _formError = 'Motivo: máximo 240 caracteres.');
      return;
    }
    if (preview.hasPartialStockSkip && !_confirmPartial) {
      setState(
        () => _formError =
            'Confirmá que entendés que parte del stock no se revertirá.',
      );
      return;
    }

    setState(() {
      _submitting = true;
      _formError = null;
    });
    try {
      await widget.purchasesApi.voidPurchase(
        widget.storeId,
        widget.detail.summary.id,
        PurchaseVoidRequest(
          opId: ClientMutationId.newId(),
          reason: reason,
          confirmPartialStock: preview.hasPartialStockSkip
              ? _confirmPartial
              : true,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _formError = isLikelyNetworkFailure(e)
            ? 'Sin conexión: la anulación no se envió.'
            : e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final preview = _preview;
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
            child: _loadingPreview
                ? const Center(child: CircularProgressIndicator())
                : _previewError != null
                    ? ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(
                            'Anular factura',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 16),
                          Text(_previewError!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _loadPreview,
                            child: const Text('Reintentar preview'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cerrar'),
                          ),
                        ],
                      )
                    : ListView(
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
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (preview?.voidMode != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              'Modo: ${preview!.voidMode}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: PosSaleUi.textMuted),
                            ),
                          ],
                          if (preview != null && !preview.canVoid) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                preview.blockers.isEmpty
                                    ? 'No se puede anular.'
                                    : 'No se puede anular: ${preview.blockers.join(', ')}',
                                style: const TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Impacto estimado',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          _kv(
                            'Saldo (deuda)',
                            '${preview?.debt.amountDueFunctionalBefore ?? '—'} → '
                            '${preview?.debt.amountDueFunctionalAfter ?? '0'}',
                          ),
                          _kv(
                            'Abonos',
                            preview?.payments.willReversePayments == true
                                ? 'Se marcarán revertidos '
                                    '(${preview!.payments.amountPaidFunctional ?? '—'})'
                                : 'Sin abonos a revertir',
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Líneas / stock',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          if (preview == null || preview.lines.isEmpty)
                            const Text('Sin líneas en el preview.')
                          else
                            ...preview.lines.map(
                              (l) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(l.productName ?? l.productId),
                                  subtitle: Text(
                                    'Comprado ${l.quantityPurchased} · '
                                    'Revertible ${l.quantityReversible} · '
                                    'Omitido ${l.quantitySkipped}'
                                    '${l.stockOnHand == null ? '' : ' · Stock ${l.stockOnHand}'}'
                                    '${l.skipReason == null ? '' : '\n${l.skipReason}'}',
                                  ),
                                  isThreeLine: l.skipReason != null,
                                ),
                              ),
                            ),
                          if (preview != null && preview.warnings.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ...preview.warnings.map(
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
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (preview != null && preview.hasPartialStockSkip) ...[
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _confirmPartial,
                              onChanged: _submitting
                                  ? null
                                  : (v) => setState(
                                        () => _confirmPartial = v ?? false,
                                      ),
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
                            enabled: !_submitting &&
                                (preview?.canVoid ?? false),
                            maxLength: 240,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Motivo de anulación',
                              hintText:
                                  'Ej. Factura duplicada / error de carga',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if (_formError != null) ...[
                            Text(
                              _formError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          FilledButton(
                            onPressed: _submitting ||
                                    preview == null ||
                                    !preview.canVoid
                                ? null
                                : _onConfirm,
                            child: _submitting
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Confirmar anulación'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed:
                                _submitting ? null : () => Navigator.pop(context),
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
