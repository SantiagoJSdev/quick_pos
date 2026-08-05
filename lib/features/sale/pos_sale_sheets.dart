import 'package:flutter/material.dart';

import '../../core/pos/money_string_math.dart';
import '../../core/pos/pos_cash_advance.dart';
import 'pos_sale_ui_tokens.dart';

/// Bottom sheet: numpad para cantidad decimal (peso, etc.).
Future<String?> showPosQuantityNumpadSheet(
  BuildContext context, {
  required String productName,
  required String initialQuantity,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _QuantityNumpadSheet(
      productName: productName,
      initialQuantity: initialQuantity,
    ),
  );
}

class _QuantityNumpadSheet extends StatefulWidget {
  const _QuantityNumpadSheet({
    required this.productName,
    required this.initialQuantity,
  });

  final String productName;
  final String initialQuantity;

  @override
  State<_QuantityNumpadSheet> createState() => _QuantityNumpadSheetState();
}

class _QuantityNumpadSheetState extends State<_QuantityNumpadSheet> {
  late String _buffer;

  @override
  void initState() {
    super.initState();
    _buffer = widget.initialQuantity.trim().replaceAll(',', '.');
    if (_buffer.isEmpty) _buffer = '1';
  }

  void _tap(String key) {
    setState(() {
      if (key == 'del') {
        _buffer = _buffer.isNotEmpty
            ? _buffer.substring(0, _buffer.length - 1)
            : '';
        if (_buffer.isEmpty || _buffer == '-') _buffer = '0';
        return;
      }
      if (key == '.') {
        if (!_buffer.contains('.')) {
          _buffer = _buffer.isEmpty ? '0.' : '$_buffer.';
        }
        return;
      }
      if (_buffer == '0' && key != '.') {
        _buffer = key;
        return;
      }
      if (_buffer.length >= 8) return;
      _buffer += key;
    });
  }

  void _confirm() {
    final v = double.tryParse(_buffer.replaceAll(',', '.'));
    if (v == null || v <= 0) {
      Navigator.pop(context);
      return;
    }
    Navigator.pop(context, _buffer.replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(
        color: PosSaleUi.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.fromBorderSide(BorderSide(color: PosSaleUi.border)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
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
          const SizedBox(height: 20),
          const Text(
            'Ajustar cantidad',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PosSaleUi.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.productName,
            style: const TextStyle(fontSize: 12, color: PosSaleUi.textMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: PosSaleUi.surface3,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PosSaleUi.border),
            ),
            child: Text(
              _buffer.isEmpty ? '0' : _buffer,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: PosSaleUi.text,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              for (final k in ['7', '8', '9', '4', '5', '6', '1', '2', '3'])
                _NumKey(label: k, onTap: () => _tap(k)),
              _NumKey(label: '.', muted: true, onTap: () => _tap('.')),
              _NumKey(label: '0', onTap: () => _tap('0')),
              _NumKey(label: '⌫', muted: true, onTap: () => _tap('del')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PosSaleUi.textMuted,
                    side: const BorderSide(color: PosSaleUi.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _confirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: PosSaleUi.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Confirmar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumKey extends StatelessWidget {
  const _NumKey({required this.label, required this.onTap, this.muted = false});

  final String label;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PosSaleUi.surface3,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: muted ? PosSaleUi.textMuted : PosSaleUi.text,
            ),
          ),
        ),
      ),
    );
  }
}

enum PosWeightInputMode { grams, documentAmount, functionalAmount }

class PosWeightedAddResult {
  const PosWeightedAddResult({
    required this.quantityKg,
    required this.displayGrams,
    required this.lineAmountFunctional,
    required this.lineAmountDocument,
  });

  final String quantityKg;
  final String displayGrams;
  final String lineAmountFunctional;
  final String lineAmountDocument;
}

/// Resultado del sheet de peso: agregar/actualizar cantidad o quitar del ticket.
sealed class PosWeightedSheetOutcome {
  const PosWeightedSheetOutcome();
}

final class PosWeightedSheetAdded extends PosWeightedSheetOutcome {
  const PosWeightedSheetAdded(this.result);
  final PosWeightedAddResult result;
}

final class PosWeightedSheetRemoved extends PosWeightedSheetOutcome {
  const PosWeightedSheetRemoved();
}

Future<PosWeightedSheetOutcome?> showPosWeightedAddSheet(
  BuildContext context, {
  required String productName,
  required String functionalCode,
  required String documentCode,
  required String pricePerKgFunctional,
  required String pricePerKgDocument,
  required String fxRateDocumentPerFunctional,
  String? initialGrams,
  /// Si true (línea ya en el carrito), muestra «Quitar del ticket».
  bool allowRemoveFromCart = false,
}) {
  return showModalBottomSheet<PosWeightedSheetOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _WeightedAddSheet(
      productName: productName,
      functionalCode: functionalCode,
      documentCode: documentCode,
      pricePerKgFunctional: pricePerKgFunctional,
      pricePerKgDocument: pricePerKgDocument,
      fxRateDocumentPerFunctional: fxRateDocumentPerFunctional,
      initialGrams: initialGrams,
      allowRemoveFromCart: allowRemoveFromCart,
    ),
  );
}

class _WeightedAddSheet extends StatefulWidget {
  const _WeightedAddSheet({
    required this.productName,
    required this.functionalCode,
    required this.documentCode,
    required this.pricePerKgFunctional,
    required this.pricePerKgDocument,
    required this.fxRateDocumentPerFunctional,
    this.initialGrams,
    this.allowRemoveFromCart = false,
  });

  final String productName;
  final String functionalCode;
  final String documentCode;
  final String pricePerKgFunctional;
  final String pricePerKgDocument;
  final String fxRateDocumentPerFunctional;
  final String? initialGrams;
  final bool allowRemoveFromCart;

  @override
  State<_WeightedAddSheet> createState() => _WeightedAddSheetState();
}

class _WeightedAddSheetState extends State<_WeightedAddSheet> {
  PosWeightInputMode _mode = PosWeightInputMode.functionalAmount;
  final _gramsCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _funcCtrl = TextEditingController();
  String? _error;
  bool _syncing = false;

  /// Evita que un `onChanged` de otro campo dispare [_recompute] mientras
  /// sincronizamos los tres TextField (si no, p. ej. gramos a 1 decimal
  /// “363.6” recalcula Bs y da 1015.90 en vez de 2×508=1016).
  bool _updatingControllers = false;

  @override
  void initState() {
    super.initState();
    final g = widget.initialGrams?.trim();
    if (g != null && g.isNotEmpty) {
      _gramsCtrl.text = g;
    }
    _recompute(from: PosWeightInputMode.grams, userInput: _gramsCtrl.text);
  }

  @override
  void dispose() {
    _gramsCtrl.dispose();
    _docCtrl.dispose();
    _funcCtrl.dispose();
    super.dispose();
  }

  double _p(String raw) =>
      double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;

  String _fmt(double v, int fd) => v.toStringAsFixed(fd);

  static String _normDecimal(String raw) => raw.trim().replaceAll(',', '.');

  bool get _priceValid =>
      _p(widget.pricePerKgFunctional) > 0 && _p(widget.pricePerKgDocument) > 0;

  void _setControllersSynced({
    required String gramsText,
    required String docText,
    required String funcText,
  }) {
    _updatingControllers = true;
    try {
      _gramsCtrl.text = gramsText;
      _docCtrl.text = docText;
      _funcCtrl.text = funcText;
    } finally {
      _updatingControllers = false;
    }
  }

  void _recompute({
    required PosWeightInputMode from,
    required String userInput,
  }) {
    if (_syncing || _updatingControllers) return;
    _syncing = true;
    final priceF = widget.pricePerKgFunctional.trim();
    final fx = widget.fxRateDocumentPerFunctional.trim();
    final preserved = userInput.trim().replaceAll(',', '.');
    final raw = preserved;
    final input = _p(raw);
    var gramsText = '';
    var docText = '';
    var funcText = '';

    void applyPartial() {
      _setControllersSynced(
        gramsText: from == PosWeightInputMode.grams ? preserved : '',
        docText: from == PosWeightInputMode.documentAmount ? preserved : '',
        funcText: from == PosWeightInputMode.functionalAmount ? preserved : '',
      );
    }

    if (raw.isEmpty || _p(priceF) <= 0 || _p(fx) <= 0) {
      applyPartial();
      _syncing = false;
      setState(() {});
      return;
    }
    if (input <= 0) {
      applyPartial();
      _syncing = false;
      setState(() {});
      return;
    }

    if (from == PosWeightInputMode.grams) {
      gramsText = preserved;
      final kgStr = MoneyStringMath.divide(raw, '1000', fractionDigits: 10);
      funcText = MoneyStringMath.multiply(kgStr, priceF, fractionDigits: 6);
      docText = MoneyStringMath.multiply(funcText, fx, fractionDigits: 2);
    } else if (from == PosWeightInputMode.documentAmount) {
      docText = preserved;
      funcText = MoneyStringMath.divide(raw, fx, fractionDigits: 6);
      final kgStr = MoneyStringMath.divide(funcText, priceF, fractionDigits: 10);
      final grams = _p(MoneyStringMath.multiply(kgStr, '1000', fractionDigits: 4));
      gramsText = grams > 0 ? _fmt(grams, 2) : '';
    } else {
      funcText = preserved;
      docText = MoneyStringMath.multiply(raw, fx, fractionDigits: 2);
      final kgStr = MoneyStringMath.divide(raw, priceF, fractionDigits: 10);
      final grams = _p(MoneyStringMath.multiply(kgStr, '1000', fractionDigits: 4));
      gramsText = grams > 0 ? _fmt(grams, 2) : '';
    }
    _setControllersSynced(
      gramsText: gramsText,
      docText: docText,
      funcText: funcText,
    );
    _syncing = false;
    setState(() {});
  }

  String get _quantityKg {
    final raw = _normDecimal(_gramsCtrl.text);
    if (raw.isEmpty || _p(raw) <= 0) return '0';
    return MoneyStringMath.divide(raw, '1000', fractionDigits: 6);
  }

  void _confirm() {
    setState(() => _error = null);
    if (!_priceValid) {
      setState(() => _error = 'Precio por kg no válido para este producto.');
      return;
    }
    final priceF = widget.pricePerKgFunctional.trim();
    final fx = widget.fxRateDocumentPerFunctional.trim();
    late final String lineFunc;
    late final String lineDoc;
    late final String qtyKg;
    late final String displayG;
    switch (_mode) {
      case PosWeightInputMode.functionalAmount:
        lineFunc = MoneyStringMath.multiply(
          '1',
          _normDecimal(_funcCtrl.text),
          fractionDigits: 6,
        );
        if (_p(lineFunc) <= 0) {
          setState(
            () => _error = 'Ingresá un monto funcional mayor que 0.',
          );
          return;
        }
        lineDoc = MoneyStringMath.multiply(lineFunc, fx, fractionDigits: 2);
        qtyKg = MoneyStringMath.divide(lineFunc, priceF, fractionDigits: 6);
        displayG = _fmt(
          _p(MoneyStringMath.multiply(qtyKg, '1000', fractionDigits: 4)),
          1,
        );
        break;
      case PosWeightInputMode.documentAmount:
        lineDoc = MoneyStringMath.multiply(
          '1',
          _normDecimal(_docCtrl.text),
          fractionDigits: 2,
        );
        if (_p(lineDoc) <= 0) {
          setState(
            () => _error = 'Ingresá un monto en moneda documento mayor que 0.',
          );
          return;
        }
        lineFunc = MoneyStringMath.divide(lineDoc, fx, fractionDigits: 6);
        qtyKg = MoneyStringMath.divide(lineFunc, priceF, fractionDigits: 6);
        displayG = _fmt(
          _p(MoneyStringMath.multiply(qtyKg, '1000', fractionDigits: 4)),
          1,
        );
        break;
      case PosWeightInputMode.grams:
        final gRaw = _normDecimal(_gramsCtrl.text);
        if (gRaw.isEmpty || _p(gRaw) <= 0) {
          setState(() => _error = 'Ingresá un peso en gramos mayor que 0.');
          return;
        }
        displayG = _fmt(_p(gRaw), 1);
        qtyKg = MoneyStringMath.divide(gRaw, '1000', fractionDigits: 6);
        lineFunc = MoneyStringMath.multiply(qtyKg, priceF, fractionDigits: 6);
        lineDoc = MoneyStringMath.multiply(lineFunc, fx, fractionDigits: 2);
        break;
    }
    Navigator.pop(
      context,
      PosWeightedSheetAdded(
        PosWeightedAddResult(
          quantityKg: qtyKg,
          displayGrams: displayG,
          lineAmountFunctional: MoneyStringMath.multiply(
            '1',
            lineFunc,
            fractionDigits: 2,
          ),
          lineAmountDocument: lineDoc,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rate = widget.fxRateDocumentPerFunctional;
    return Container(
      decoration: const BoxDecoration(
        color: PosSaleUi.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.fromBorderSide(BorderSide(color: PosSaleUi.border)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + bottom),
      child: SingleChildScrollView(
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
            const SizedBox(height: 12),
            const Text(
              'Agregar por peso',
              style: TextStyle(
                color: PosSaleUi.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Text(
              '${widget.pricePerKgFunctional} ${widget.functionalCode}/kg  ·  '
              '${widget.pricePerKgDocument} ${widget.documentCode}/kg',
              style: const TextStyle(
                color: PosSaleUi.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '1 ${widget.functionalCode} = $rate ${widget.documentCode}',
              style: const TextStyle(color: PosSaleUi.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            SegmentedButton<PosWeightInputMode>(
              segments: [
                ButtonSegment(
                  value: PosWeightInputMode.functionalAmount,
                  label: Text(widget.functionalCode),
                ),
                ButtonSegment(
                  value: PosWeightInputMode.documentAmount,
                  label: Text(widget.documentCode),
                ),
                const ButtonSegment(
                  value: PosWeightInputMode.grams,
                  label: Text('Gramos'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (next) {
                setState(() => _mode = next.first);
              },
            ),
            const SizedBox(height: 12),
            if (_mode == PosWeightInputMode.grams)
              TextField(
                controller: _gramsCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  if (_updatingControllers) return;
                  _recompute(from: PosWeightInputMode.grams, userInput: v);
                },
                decoration: const InputDecoration(
                  labelText: 'Peso (g)',
                  border: OutlineInputBorder(),
                ),
              ),
            if (_mode == PosWeightInputMode.documentAmount)
              TextField(
                controller: _docCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  if (_updatingControllers) return;
                  _recompute(
                    from: PosWeightInputMode.documentAmount,
                    userInput: v,
                  );
                },
                decoration: InputDecoration(
                  labelText: 'Monto ${widget.documentCode}',
                  border: const OutlineInputBorder(),
                ),
              ),
            if (_mode == PosWeightInputMode.functionalAmount)
              TextField(
                controller: _funcCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (v) {
                  if (_updatingControllers) return;
                  _recompute(
                    from: PosWeightInputMode.functionalAmount,
                    userInput: v,
                  );
                },
                decoration: InputDecoration(
                  labelText: 'Monto ${widget.functionalCode}',
                  border: const OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: PosSaleUi.surface3,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PosSaleUi.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cantidad: ${_gramsCtrl.text.isEmpty ? '0' : _gramsCtrl.text} g ($_quantityKg kg)',
                    style: const TextStyle(color: PosSaleUi.text, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Importe: ${_docCtrl.text.isEmpty ? '0.00' : _docCtrl.text} ${widget.documentCode}',
                    style: const TextStyle(
                      color: PosSaleUi.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Ref: ${_funcCtrl.text.isEmpty ? '0.00' : _funcCtrl.text} ${widget.functionalCode}',
                    style: const TextStyle(
                      color: PosSaleUi.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: PosSaleUi.error, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            if (widget.allowRemoveFromCart) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(
                    context,
                    const PosWeightedSheetRemoved(),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  label: const Text('Quitar del ticket'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: PosSaleUi.error,
                    side: const BorderSide(color: PosSaleUi.error),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _confirm,
                    child: Text(
                      widget.allowRemoveFromCart ? 'Actualizar' : 'Agregar',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Resultado del sheet de avance de efectivo.
class PosCashAdvanceSheetResult {
  const PosCashAdvanceSheetResult({
    required this.advanceBaseDocument,
    required this.feeDocument,
    required this.totalChargeDocument,
  });

  final String advanceBaseDocument;
  final String feeDocument;

  /// Avance + comisión (precio unitario qty=1 en el ticket).
  final String totalChargeDocument;
}

sealed class PosCashAdvanceSheetOutcome {}

class PosCashAdvanceSheetConfirmed extends PosCashAdvanceSheetOutcome {
  PosCashAdvanceSheetConfirmed(this.result);
  final PosCashAdvanceSheetResult result;
}

class PosCashAdvanceSheetRemoved extends PosCashAdvanceSheetOutcome {}

/// Bottom sheet: monto del avance → comisión [PosCashAdvance.feePercentLabel].
Future<PosCashAdvanceSheetOutcome?> showPosCashAdvanceSheet(
  BuildContext context, {
  required String productName,
  required String documentCode,
  String? initialAdvanceBase,
  bool allowRemoveFromCart = false,
}) {
  return showModalBottomSheet<PosCashAdvanceSheetOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CashAdvanceSheet(
      productName: productName,
      documentCode: documentCode,
      initialAdvanceBase: initialAdvanceBase,
      allowRemoveFromCart: allowRemoveFromCart,
    ),
  );
}

class _CashAdvanceSheet extends StatefulWidget {
  const _CashAdvanceSheet({
    required this.productName,
    required this.documentCode,
    this.initialAdvanceBase,
    this.allowRemoveFromCart = false,
  });

  final String productName;
  final String documentCode;
  final String? initialAdvanceBase;
  final bool allowRemoveFromCart;

  @override
  State<_CashAdvanceSheet> createState() => _CashAdvanceSheetState();
}

class _CashAdvanceSheetState extends State<_CashAdvanceSheet> {
  late String _buffer;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAdvanceBase?.trim().replaceAll(',', '.') ?? '';
    _buffer = PosCashAdvance.isPositiveAmount(initial) ? initial : '';
  }

  String get _fee {
    if (!PosCashAdvance.isPositiveAmount(_buffer)) return '0.00';
    return PosCashAdvance.feeFromAdvanceAmount(_buffer);
  }

  String get _total {
    if (!PosCashAdvance.isPositiveAmount(_buffer)) return '0.00';
    return PosCashAdvance.totalChargeFromAdvanceAmount(_buffer);
  }

  void _tap(String key) {
    setState(() {
      if (key == 'del') {
        _buffer = _buffer.isNotEmpty
            ? _buffer.substring(0, _buffer.length - 1)
            : '';
        return;
      }
      if (key == '.') {
        if (!_buffer.contains('.')) {
          _buffer = _buffer.isEmpty ? '0.' : '$_buffer.';
        }
        return;
      }
      if (_buffer == '0' && key != '.') {
        _buffer = key;
        return;
      }
      if (_buffer.length >= 12) return;
      _buffer += key;
    });
  }

  void _confirm() {
    if (!PosCashAdvance.isPositiveAmount(_buffer)) return;
    final base = _buffer.replaceAll(',', '.');
    final fee = PosCashAdvance.feeFromAdvanceAmount(base);
    final total = PosCashAdvance.totalChargeFromAdvanceAmount(base);
    if (!PosCashAdvance.isPositiveAmount(fee) ||
        !PosCashAdvance.isPositiveAmount(total)) {
      return;
    }
    Navigator.pop(
      context,
      PosCashAdvanceSheetConfirmed(
        PosCashAdvanceSheetResult(
          advanceBaseDocument: base,
          feeDocument: fee,
          totalChargeDocument: total,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottom = mq.padding.bottom;
    final doc = widget.documentCode.trim().toUpperCase();
    final fee = _fee;
    final total = _total;
    final valid = PosCashAdvance.isPositiveAmount(_buffer) &&
        PosCashAdvance.isPositiveAmount(fee) &&
        PosCashAdvance.isPositiveAmount(total);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.92),
        child: Container(
          decoration: const BoxDecoration(
            color: PosSaleUi.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.fromBorderSide(BorderSide(color: PosSaleUi.border)),
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 12, 24, 16 + bottom),
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
                const SizedBox(height: 12),
                const Text(
                  'Avance de efectivo',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: PosSaleUi.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.productName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: PosSaleUi.textMuted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  'Monto del avance ($doc)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PosSaleUi.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: PosSaleUi.surface3,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PosSaleUi.border),
                  ),
                  child: Text(
                    _buffer.isEmpty ? '0' : _buffer,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: PosSaleUi.text,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: PosSaleUi.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: PosSaleUi.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Comisión ${PosCashAdvance.feePercentLabel}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: PosSaleUi.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$fee $doc',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: PosSaleUi.primary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Total a cobrar (avance + comisión)',
                        style: TextStyle(
                          fontSize: 11,
                          color: PosSaleUi.textMuted,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$total $doc',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: PosSaleUi.text,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 2.0,
                  children: [
                    for (final k in [
                      '7',
                      '8',
                      '9',
                      '4',
                      '5',
                      '6',
                      '1',
                      '2',
                      '3',
                    ])
                      _NumKey(label: k, onTap: () => _tap(k)),
                    _NumKey(label: '.', muted: true, onTap: () => _tap('.')),
                    _NumKey(label: '0', onTap: () => _tap('0')),
                    _NumKey(label: '⌫', muted: true, onTap: () => _tap('del')),
                  ],
                ),
                if (widget.allowRemoveFromCart) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, PosCashAdvanceSheetRemoved()),
                    child: const Text(
                      'Quitar del ticket',
                      style: TextStyle(color: Colors.orangeAccent),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: PosSaleUi.textMuted,
                          side: const BorderSide(color: PosSaleUi.border),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Cancelar'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: valid ? _confirm : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: PosSaleUi.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          widget.allowRemoveFromCart
                              ? 'Actualizar'
                              : 'Agregar',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
