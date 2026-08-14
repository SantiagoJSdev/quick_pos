import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/purchases_api.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/purchase.dart';
import '../../core/network/network_errors.dart';
import '../../core/storage/local_prefs.dart';
import '../sale/pos_sale_ui_tokens.dart';
import '../settings/store_advanced_config_screen.dart';
import 'purchase_void_sheet.dart';

/// Detalle de factura + abonos (`GET /purchases/:id`, `POST .../payments`).
class PurchaseDetailScreen extends StatefulWidget {
  const PurchaseDetailScreen({
    super.key,
    required this.storeId,
    required this.purchaseId,
    required this.purchasesApi,
    this.localPrefs,
    this.shellOnline = true,
  });

  final String storeId;
  final String purchaseId;
  final PurchasesApi purchasesApi;
  final LocalPrefs? localPrefs;
  final bool shellOnline;

  @override
  State<PurchaseDetailScreen> createState() => _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends State<PurchaseDetailScreen> {
  PurchaseDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _paying = false;
  bool _didChange = false;
  String _functionalCode = 'USD';

  @override
  void initState() {
    super.initState();
    _resolveFunctionalCurrency();
    _load();
  }

  Future<void> _resolveFunctionalCurrency() async {
    final prefs = widget.localPrefs;
    if (prefs == null) return;
    try {
      final settings = await prefs.loadBusinessSettingsCache(widget.storeId);
      final code = settings?.functionalCurrency.code.trim().toUpperCase() ?? '';
      if (code.isNotEmpty && mounted) {
        setState(() => _functionalCode = code);
      }
    } catch (_) {
      // fallback USD
    }
  }

  Future<void> _load() async {
    if (!widget.shellOnline) {
      setState(() {
        _loading = false;
        _error = 'Sin conexión. El detalle de factura requiere internet.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await widget.purchasesApi.getPurchase(
        widget.storeId,
        widget.purchaseId,
      );
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openVoidFlow() async {
    final d = _detail;
    if (d == null) return;
    if (d.summary.isVoided) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Esta factura ya está anulada.')),
      );
      return;
    }
    if (!widget.shellOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La anulación requiere conexión a internet.'),
        ),
      );
      return;
    }
    final ok = await showStoreConfigPinDialog(context);
    if (!mounted || ok != true) return;
    final voided = await showPurchaseVoidSheet(
      context: context,
      storeId: widget.storeId,
      purchasesApi: widget.purchasesApi,
      detail: d,
    );
    if (!mounted) return;
    if (voided == true) {
      _didChange = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Factura anulada.')),
      );
      await _load();
    }
  }

  Future<void> _showPaymentSheet({bool payInFull = false}) async {
    final d = _detail;
    if (d == null) return;
    if (!widget.shellOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Los abonos requieren conexión a internet.'),
        ),
      );
      return;
    }
    final due = d.summary.amountDueFunctional?.trim() ?? '';
    final result = await showModalBottomSheet<_PaymentSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PurchasePaymentSheet(
        payInFull: payInFull,
        amountDue: due,
        functionalCurrencyCode: _functionalCode,
      ),
    );
    if (result == null || !mounted) return;
    if (result.amount.isEmpty || !_isValidAmount(result.amount)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indicá un monto válido.')),
      );
      return;
    }
    await _submitPayment(
      amount: result.amount.replaceAll(',', '.'),
      method: result.method.isEmpty ? 'CASH' : result.method,
    );
  }

  static bool _isValidAmount(String raw) {
    final n = double.tryParse(raw.trim().replaceAll(',', '.'));
    return n != null && n > 0;
  }

  Future<void> _submitPayment({
    required String amount,
    required String method,
  }) async {
    setState(() => _paying = true);
    try {
      await widget.purchasesApi.createPayment(
        widget.storeId,
        widget.purchaseId,
        {
          'amountFunctional': amount,
          'method': method,
          'opId': ClientMutationId.newId(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Abono registrado.')),
      );
      _didChange = true;
      await _load();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessageForSupport)),
      );
    } catch (e) {
      if (!mounted) return;
      final msg = isLikelyNetworkFailure(e)
          ? 'Sin conexión: el abono no se envió. Reintentá online.'
          : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  String _moneyLabel(String label) => '$label ($_functionalCode)';

  String _fmtMoney(String? amount) {
    final a = amount?.trim();
    if (a == null || a.isEmpty) return '—';
    return '$a $_functionalCode';
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    final open = d?.summary.isOpen ?? false;
    final voided = d?.summary.isVoided ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle factura'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_didChange),
        ),
        actions: [
          if (d != null && !voided)
            IconButton(
              tooltip: 'Anular factura',
              icon: const Icon(Icons.cancel_outlined),
              onPressed: _paying ? null : _openVoidFlow,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading || _paying ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && d == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : d == null
                  ? const Center(child: Text('Sin datos'))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                      children: [
                        Text(
                          d.summary.supplierInvoiceReference
                                      ?.trim()
                                      .isNotEmpty ==
                                  true
                              ? 'Nº ${d.summary.supplierInvoiceReference!.trim()}'
                              : 'Sin Nº de factura',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (voided) 'ANULADA',
                            if ((d.summary.supplierName ?? '').isNotEmpty)
                              d.summary.supplierName!,
                            if ((d.summary.paymentStatus ?? '').isNotEmpty)
                              d.summary.paymentStatus!.toUpperCase(),
                            if ((d.summary.createdAt ?? '').isNotEmpty)
                              d.summary.createdAt!,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: voided
                                    ? Colors.redAccent
                                    : PosSaleUi.textMuted,
                              ),
                        ),
                        if (voided &&
                            (d.summary.voidReason ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Motivo: ${d.summary.voidReason}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 16),
                        _kv(
                          _moneyLabel('Total'),
                          _fmtMoney(d.summary.totalFunctional),
                        ),
                        _kv(
                          _moneyLabel('Pagado'),
                          _fmtMoney(d.summary.amountPaidFunctional),
                        ),
                        _kv(
                          _moneyLabel('Saldo'),
                          _fmtMoney(d.summary.amountDueFunctional),
                        ),
                        if ((d.summary.dueDate ?? '').isNotEmpty)
                          _kv('Vence', d.summary.dueDate!),
                        const SizedBox(height: 12),
                        if (!voided)
                          OutlinedButton.icon(
                            onPressed: _paying ? null : _openVoidFlow,
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Anular factura'),
                          ),
                        const SizedBox(height: 20),
                        Text(
                          'Líneas',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (d.lines.isEmpty)
                          const Text('Sin líneas en la respuesta.')
                        else
                          ...d.lines.map(
                            (l) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(l.productName ?? l.productId),
                              subtitle: Text(
                                '${l.quantity} × ${l.unitCost}',
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Abonos',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (d.payments.isEmpty)
                          const Text('Sin abonos registrados.')
                        else
                          ...d.payments.map(
                            (p) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.payments_outlined),
                              title: Text(_fmtMoney(p.amountFunctional)),
                              subtitle: Text(
                                [
                                  if ((p.method ?? '').isNotEmpty) p.method!,
                                  if ((p.createdAt ?? '').isNotEmpty)
                                    p.createdAt!,
                                ].join(' · '),
                              ),
                            ),
                          ),
                      ],
                    ),
      bottomNavigationBar: open && d != null && !voided
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _paying
                            ? null
                            : () => _showPaymentSheet(payInFull: false),
                        child: const Text('Abonar'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _paying
                            ? null
                            : () => _showPaymentSheet(payInFull: true),
                        child: const Text('Pagar todo'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: const TextStyle(color: PosSaleUi.textMuted)),
          ),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PaymentSheetResult {
  const _PaymentSheetResult({required this.amount, required this.method});

  final String amount;
  final String method;
}

/// Sheet con controllers propios (evita dispose prematuro al cerrar).
class _PurchasePaymentSheet extends StatefulWidget {
  const _PurchasePaymentSheet({
    required this.payInFull,
    required this.amountDue,
    required this.functionalCurrencyCode,
  });

  final bool payInFull;
  final String amountDue;
  final String functionalCurrencyCode;

  @override
  State<_PurchasePaymentSheet> createState() => _PurchasePaymentSheetState();
}

class _PurchasePaymentSheetState extends State<_PurchasePaymentSheet> {
  late final TextEditingController _amountCtrl;
  late final TextEditingController _methodCtrl;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.payInFull ? widget.amountDue : '',
    );
    _methodCtrl = TextEditingController(text: 'CASH');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _methodCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.functionalCurrencyCode;
    final due = widget.amountDue;
    final dueLabel = due.isEmpty ? '—' : '$due $code';
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.payInFull ? 'Marcar como pagada' : 'Registrar abono',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ingresá el monto en $code (moneda principal / funcional de la tienda). '
            'Saldo actual: $dueLabel',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.textMuted,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            autofocus: !widget.payInFull,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: 'Monto ($code)',
              hintText: 'Ej. 25.00',
              suffixText: code,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _methodCtrl,
            decoration: const InputDecoration(
              labelText: 'Método (ej. CASH, TRANSFER)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                context,
                _PaymentSheetResult(
                  amount: _amountCtrl.text.trim(),
                  method: _methodCtrl.text.trim(),
                ),
              );
            },
            child: Text(
              widget.payInFull ? 'Pagar saldo' : 'Registrar abono',
            ),
          ),
        ],
      ),
    );
  }
}
