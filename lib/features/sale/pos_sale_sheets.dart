import 'package:flutter/material.dart';

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
        _buffer = _buffer.isNotEmpty ? _buffer.substring(0, _buffer.length - 1) : '';
        if (_buffer.isEmpty || _buffer == '-') _buffer = '0';
        return;
      }
      if (key == '.') {
        if (!_buffer.contains('.')) _buffer = _buffer.isEmpty ? '0.' : '$_buffer.';
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
  const _NumKey({
    required this.label,
    required this.onTap,
    this.muted = false,
  });

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
