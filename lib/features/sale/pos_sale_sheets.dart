import 'package:flutter/material.dart';

import '../../core/pos/money_string_math.dart';
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

Future<PosWeightedAddResult?> showPosWeightedAddSheet(
  BuildContext context, {
  required String productName,
  required String functionalCode,
  required String documentCode,
  required String pricePerKgFunctional,
  required String pricePerKgDocument,
  required String fxRateDocumentPerFunctional,
  String? initialGrams,
}) {
  return showModalBottomSheet<PosWeightedAddResult>(
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
  });

  final String productName;
  final String functionalCode;
  final String documentCode;
  final String pricePerKgFunctional;
  final String pricePerKgDocument;
  final String fxRateDocumentPerFunctional;
  final String? initialGrams;

  @override
  State<_WeightedAddSheet> createState() => _WeightedAddSheetState();
}

class _WeightedAddSheetState extends State<_WeightedAddSheet> {
  PosWeightInputMode _mode = PosWeightInputMode.grams;
  final _gramsCtrl = TextEditingController();
  final _docCtrl = TextEditingController();
  final _funcCtrl = TextEditingController();
  String? _error;
  bool _syncing = false;

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

  bool get _priceValid =>
      _p(widget.pricePerKgFunctional) > 0 && _p(widget.pricePerKgDocument) > 0;

  void _recompute({
    required PosWeightInputMode from,
    required String userInput,
  }) {
    if (_syncing) return;
    _syncing = true;
    final priceFunc = _p(widget.pricePerKgFunctional);
    final fx = _p(widget.fxRateDocumentPerFunctional);
    final input = _p(userInput);
    var grams = 0.0;
    var kg = 0.0;
    var amountFunc = 0.0;
    var amountDoc = 0.0;
    if (priceFunc > 0 && fx > 0 && input > 0) {
      if (from == PosWeightInputMode.grams) {
        grams = input;
        kg = grams / 1000;
        amountFunc = kg * priceFunc;
        amountDoc = amountFunc * fx;
      } else if (from == PosWeightInputMode.documentAmount) {
        amountDoc = input;
        amountFunc = amountDoc / fx;
        kg = amountFunc / priceFunc;
        grams = kg * 1000;
      } else {
        amountFunc = input;
        amountDoc = amountFunc * fx;
        kg = amountFunc / priceFunc;
        grams = kg * 1000;
      }
    }
    _gramsCtrl.text = grams > 0 ? _fmt(grams, 1) : '';
    _docCtrl.text = amountDoc > 0 ? _fmt(amountDoc, 2) : '';
    _funcCtrl.text = amountFunc > 0 ? _fmt(amountFunc, 2) : '';
    _syncing = false;
    setState(() {});
  }

  String get _quantityKg {
    final grams = _p(_gramsCtrl.text);
    return grams <= 0
        ? '0'
        : MoneyStringMath.divide(_fmt(grams, 4), '1000', fractionDigits: 4);
  }

  void _confirm() {
    setState(() => _error = null);
    if (!_priceValid) {
      setState(() => _error = 'Precio por kg no válido para este producto.');
      return;
    }
    final grams = _p(_gramsCtrl.text);
    final doc = _p(_docCtrl.text);
    final func = _p(_funcCtrl.text);
    if (grams <= 0 || doc <= 0 || func <= 0) {
      setState(
        () => _error = 'Ingresá un valor mayor que 0 en el modo activo.',
      );
      return;
    }
    Navigator.pop(
      context,
      PosWeightedAddResult(
        quantityKg: _quantityKg,
        displayGrams: _fmt(grams, 1),
        lineAmountFunctional: _fmt(func, 2),
        lineAmountDocument: _fmt(doc, 2),
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
                const ButtonSegment(
                  value: PosWeightInputMode.grams,
                  label: Text('Gramos'),
                ),
                ButtonSegment(
                  value: PosWeightInputMode.documentAmount,
                  label: Text(widget.documentCode),
                ),
                ButtonSegment(
                  value: PosWeightInputMode.functionalAmount,
                  label: Text(widget.functionalCode),
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
                onChanged: (v) =>
                    _recompute(from: PosWeightInputMode.grams, userInput: v),
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
                onChanged: (v) => _recompute(
                  from: PosWeightInputMode.documentAmount,
                  userInput: v,
                ),
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
                onChanged: (v) => _recompute(
                  from: PosWeightInputMode.functionalAmount,
                  userInput: v,
                ),
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
                    child: const Text('Agregar'),
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
