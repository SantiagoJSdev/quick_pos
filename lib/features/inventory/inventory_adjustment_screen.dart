import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/inventory_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/network/network_errors.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/inventory_adjust_payload_builder.dart';
import '../../core/sync/pending_inventory_adjust_entry.dart';

final _decimalPositive = RegExp(r'^\d+(\.\d+)?$');

/// B3 — `POST /inventory/adjustments` con `opId` para reintentos idempotentes.
class InventoryAdjustmentScreen extends StatefulWidget {
  const InventoryAdjustmentScreen({
    super.key,
    required this.storeId,
    required this.inventoryApi,
    required this.localPrefs,
    required this.productId,
    required this.productLabel,
    this.suggestedReason,
    this.catalogInvalidationBus,
  });

  final String storeId;
  final InventoryApi inventoryApi;
  final LocalPrefs localPrefs;
  final String productId;
  final String productLabel;

  /// P. ej. alta de producto + `IN_ADJUST` “Inventario inicial” (`FRONT_INVENTORY_SUPPLIERS_MARGINS_SYNC.md` §3).
  final String? suggestedReason;

  final CatalogInvalidationBus? catalogInvalidationBus;

  @override
  State<InventoryAdjustmentScreen> createState() =>
      _InventoryAdjustmentScreenState();
}

class _InventoryAdjustmentScreenState extends State<InventoryAdjustmentScreen> {
  static const _inType = 'IN_ADJUST';
  static const _outType = 'OUT_ADJUST';

  String _type = _inType;
  final _quantity = TextEditingController();
  final _reason = TextEditingController();
  final _unitCost = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Asignado en el primer envío que pasa validación; se reutiliza en reintentos.
  String? _opId;

  /// Tras fallo de red/API: si el usuario edita el formulario, nueva operación (`_opId` nulo).
  bool _failedAwaitingRetry = false;

  @override
  void initState() {
    super.initState();
    final sr = widget.suggestedReason?.trim();
    if (sr != null && sr.isNotEmpty) {
      _reason.text = sr;
    }
    void onFieldChanged() {
      if (!_failedAwaitingRetry || !mounted) return;
      setState(() {
        _opId = null;
        _failedAwaitingRetry = false;
      });
    }

    _quantity.addListener(onFieldChanged);
    _reason.addListener(onFieldChanged);
    _unitCost.addListener(onFieldChanged);
  }

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    _unitCost.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    final qty = _quantity.text.trim();
    final reason = _reason.text.trim();
    if (!_decimalPositive.hasMatch(qty)) {
      setState(() => _error = 'La cantidad debe ser un número mayor que 0.');
      return;
    }
    final qtyVal = double.tryParse(qty);
    if (qtyVal == null || qtyVal <= 0) {
      setState(() => _error = 'La cantidad debe ser mayor que 0.');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'Indicá un motivo del ajuste (auditoría).');
      return;
    }

    final cost = _unitCost.text.trim();
    String? unitCost;
    if (_type == _inType && cost.isNotEmpty) {
      if (!_decimalPositive.hasMatch(cost)) {
        setState(() => _error = 'Costo unitario (func.): número decimal válido.');
        return;
      }
      unitCost = cost;
    }

    final payload = InventoryAdjustPayloadBuilder.fromForm(
      productId: widget.productId,
      type: _type,
      quantity: qty,
      reason: reason,
      unitCostFunctional: unitCost,
    );

    _opId ??= ClientMutationId.newId();
    final body = payload.toRestBody(opId: _opId!);

    setState(() => _loading = true);
    try {
      final res = await widget.inventoryApi.postAdjustment(widget.storeId, body);
      if (!mounted) return;
      widget.catalogInvalidationBus?.invalidateFromLocalMutation(
        productIds: {widget.productId},
      );
      final msg = res.skipped
          ? 'Ya estaba aplicado (idempotente). Stock sin cambios duplicados.'
          : 'Ajuste aplicado.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      final msg = e.userMessageForSupport;
      setState(() {
        _error = msg;
        _failedAwaitingRetry = true;
      });
    } catch (e) {
      if (!mounted) return;
      if (isLikelyNetworkFailure(e)) {
        await widget.localPrefs.appendPendingInventoryAdjust(
          PendingInventoryAdjustEntry(
            opId: _opId!,
            storeId: widget.storeId,
            payload: payload.toSyncPayload(),
            opTimestampIso: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        if (!mounted) return;
        widget.catalogInvalidationBus?.invalidateFromLocalMutation(
          productIds: {widget.productId},
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión: ajuste guardado en cola. Se enviará con sync/push '
              '(desde Venta → Sincronizar o al abrir la app).',
            ),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _error = e.toString();
        _failedAwaitingRetry = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajuste de stock')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.productLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            'UUID: ${widget.productId}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (_failedAwaitingRetry && _opId != null) ...[
            const SizedBox(height: 12),
            Text(
              'Podés reintentar: se reenvía el mismo opId para no duplicar el '
              'ajuste si el servidor ya lo aplicó.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Tipo',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment<String>(
                value: _inType,
                label: Text('Entrada'),
                icon: Icon(Icons.add_circle_outline),
              ),
              ButtonSegment<String>(
                value: _outType,
                label: Text('Salida'),
                icon: Icon(Icons.remove_circle_outline),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) {
              if (_loading) return;
              if (_failedAwaitingRetry) {
                setState(() {
                  _opId = null;
                  _failedAwaitingRetry = false;
                });
              }
              setState(() => _type = s.first);
            },
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _quantity,
            decoration: const InputDecoration(
              labelText: 'Cantidad',
              hintText: 'Unidades a ingresar o retirar',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'Motivo',
              hintText: 'Ej. inventario físico, rotura, corrección',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _unitCost,
            decoration: const InputDecoration(
              labelText: 'Costo unitario (funcional), opcional',
              hintText: 'Solo aplica a entradas; si falta usa costo medio o producto',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_loading && _type == _inType,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_failedAwaitingRetry ? 'Reintentar envío' : 'Registrar ajuste'),
          ),
        ],
      ),
    );
  }
}
