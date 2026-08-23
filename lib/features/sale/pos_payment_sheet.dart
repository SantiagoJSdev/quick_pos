import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/payment_method.dart';
import 'pos_sale_ui_tokens.dart';

final _amountPattern = RegExp(r'^\d+([.,]\d+)?$');

/// Elige método del catálogo + monto (unidad funcional). Split = abrir varias veces.
Future<PosAppliedPayment?> showPosPaymentSheet(
  BuildContext context, {
  required List<PaymentMethod> methods,
  required String functionalCode,
  required double remainingFunctional,
}) async {
  if (methods.isEmpty) return null;
  return showModalBottomSheet<PosAppliedPayment>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: PosSaleUi.surface2,
    builder: (ctx) => _PosPaymentSheet(
      methods: methods,
      functionalCode: functionalCode,
      remainingFunctional: remainingFunctional,
    ),
  );
}

class _PosPaymentSheet extends StatefulWidget {
  const _PosPaymentSheet({
    required this.methods,
    required this.functionalCode,
    required this.remainingFunctional,
  });

  final List<PaymentMethod> methods;
  final String functionalCode;
  final double remainingFunctional;

  @override
  State<_PosPaymentSheet> createState() => _PosPaymentSheetState();
}

class _PosPaymentSheetState extends State<_PosPaymentSheet> {
  PaymentMethod? _selected;
  final _amountCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.remainingFunctional > 0) {
      _amountCtrl.text = widget.remainingFunctional.toStringAsFixed(2);
    }
    if (widget.methods.length == 1) {
      _selected = widget.methods.first;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final method = _selected;
    if (method == null) {
      setState(() => _error = 'Elegí un método de pago.');
      return;
    }
    final raw = _amountCtrl.text.trim().replaceAll(',', '.');
    if (!_amountPattern.hasMatch(raw)) {
      setState(() => _error = 'Monto inválido.');
      return;
    }
    final amount = double.tryParse(raw);
    if (amount == null || amount <= 0) {
      setState(() => _error = 'El monto debe ser mayor que 0.');
      return;
    }
    Navigator.of(context).pop(
      PosAppliedPayment(
        methodCode: method.code,
        methodName: method.name,
        amountFunctional: amount,
        commissionPercent: method.commissionPercent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final func = widget.functionalCode.toUpperCase();
    final rem = widget.remainingFunctional;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
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
              'Agregar pago',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: PosSaleUi.text,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (rem > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Resta ~${rem.toStringAsFixed(2)} $func',
                style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            ...widget.methods.map((m) {
              final selected = _selected?.code == m.code;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Material(
                  color: selected
                      ? PosSaleUi.primary.withValues(alpha: 0.12)
                      : PosSaleUi.surface3,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() {
                      _selected = m;
                      _error = null;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            m.isCashLike
                                ? Icons.payments_outlined
                                : Icons.credit_card_outlined,
                            color: selected
                                ? PosSaleUi.primary
                                : PosSaleUi.textMuted,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.name,
                                  style: TextStyle(
                                    color: PosSaleUi.text,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  m.code,
                                  style: const TextStyle(
                                    color: PosSaleUi.textFaint,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (m.hasCommissionWarning)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${m.commissionPercent}%',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (_selected?.hasCommissionWarning == true) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Este método descuenta ${_selected!.commissionPercent}% '
                  'de la ganancia (lo calcula el servidor).',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              style: const TextStyle(color: PosSaleUi.text),
              decoration: InputDecoration(
                labelText: 'Monto ($func)',
                border: const OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: PosSaleUi.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(
                backgroundColor: PosSaleUi.primary,
              ),
              child: const Text('Aplicar pago'),
            ),
          ],
        ),
      ),
    );
  }
}
