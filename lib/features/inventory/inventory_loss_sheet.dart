import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/idempotency/client_mutation_id.dart';

final _positiveDecimal = RegExp(r'^\d+([.,]\d+)?$');

const _lossReasons = <String>[
  'Podrido',
  'Vencido',
  'Rotura',
  'Autoconsumo',
  'Otro',
];

/// Bottom sheet: registrar merma (`POST /inventory/losses`).
///
/// Si [isByWeight] (`unit == KG`), la cantidad se pide en kilogramos;
/// si no, en unidades.
Future<bool> showInventoryLossSheet(
  BuildContext context, {
  required String storeId,
  required InventoryApi inventoryApi,
  required String productId,
  required String productLabel,
  required bool isByWeight,
  String? currentQuantity,
  CatalogInvalidationBus? catalogInvalidationBus,
  bool shellOnline = true,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => _InventoryLossSheet(
      storeId: storeId,
      inventoryApi: inventoryApi,
      productId: productId,
      productLabel: productLabel,
      isByWeight: isByWeight,
      currentQuantity: currentQuantity,
      catalogInvalidationBus: catalogInvalidationBus,
      shellOnline: shellOnline,
    ),
  );
  return result == true;
}

class _InventoryLossSheet extends StatefulWidget {
  const _InventoryLossSheet({
    required this.storeId,
    required this.inventoryApi,
    required this.productId,
    required this.productLabel,
    required this.isByWeight,
    this.currentQuantity,
    this.catalogInvalidationBus,
    this.shellOnline = true,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final String productId;
  final String productLabel;
  final bool isByWeight;
  final String? currentQuantity;
  final CatalogInvalidationBus? catalogInvalidationBus;
  final bool shellOnline;

  @override
  State<_InventoryLossSheet> createState() => _InventoryLossSheetState();
}

class _InventoryLossSheetState extends State<_InventoryLossSheet> {
  final _quantity = TextEditingController();
  final _otherReason = TextEditingController();
  String _reason = _lossReasons.first;
  bool _loading = false;
  String? _error;
  String? _opId;

  String get _qtyLabel => widget.isByWeight ? 'Kilogramos' : 'Unidades';
  String get _qtyHint => widget.isByWeight ? 'Ej. 0.5' : 'Ej. 2';
  String get _qtySuffix => widget.isByWeight ? 'kg' : 'u.';

  @override
  void dispose() {
    _quantity.dispose();
    _otherReason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!widget.shellOnline) {
      setState(() => _error = 'Sin conexión: la merma requiere red.');
      return;
    }
    setState(() => _error = null);

    final rawQty = _quantity.text.trim().replaceAll(',', '.');
    if (!_positiveDecimal.hasMatch(rawQty)) {
      setState(() => _error = 'Cantidad inválida (número mayor que 0).');
      return;
    }
    final qtyVal = double.tryParse(rawQty);
    if (qtyVal == null || qtyVal <= 0) {
      setState(() => _error = 'La cantidad debe ser mayor que 0.');
      return;
    }
    if (!widget.isByWeight && qtyVal != qtyVal.roundToDouble()) {
      setState(
        () => _error = 'Para productos por unidad usá un número entero.',
      );
      return;
    }

    var reason = _reason;
    if (_reason == 'Otro') {
      final custom = _otherReason.text.trim();
      if (custom.isEmpty) {
        setState(() => _error = 'Indicá el motivo de la merma.');
        return;
      }
      reason = custom;
    }

    _opId ??= ClientMutationId.newId();
    setState(() => _loading = true);
    try {
      await widget.inventoryApi.postLoss(
        widget.storeId,
        productId: widget.productId,
        quantity: rawQty,
        reason: reason,
        opId: _opId,
      );
      widget.catalogInvalidationBus?.invalidateFromLocalMutation(
        productIds: {widget.productId},
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final stock = widget.currentQuantity?.trim();

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
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Registrar merma',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.productLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (stock != null && stock.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Stock actual: $stock $_qtySuffix',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _quantity,
              enabled: !_loading,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              decoration: InputDecoration(
                labelText: _qtyLabel,
                hintText: _qtyHint,
                suffixText: _qtySuffix,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Text('Motivo', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _lossReasons)
                  ChoiceChip(
                    label: Text(r),
                    selected: _reason == r,
                    onSelected: _loading
                        ? null
                        : (_) => setState(() => _reason = r),
                  ),
              ],
            ),
            if (_reason == 'Otro') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otherReason,
                enabled: !_loading,
                decoration: const InputDecoration(
                  labelText: 'Describí el motivo',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Se descuenta del stock a costo promedio. '
              'No es un ajuste manual de inventario.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      widget.isByWeight
                          ? 'Confirmar merma (kg)'
                          : 'Confirmar merma (unidades)',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
