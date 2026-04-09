import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/catalog/catalog_invalidation_bus.dart';
import '../../core/network/network_errors.dart';
import '../../core/catalog/pending_catalog_mutation_entry.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/catalog_product.dart';
import '../../core/storage/local_prefs.dart';

final _decimalPositive = RegExp(r'^\d+(\.\d+)?$');

/// Sheet M7: `POST /products-with-stock` con cabecera `Idempotency-Key` (§13.6b).
class ProductInitialStockBottomSheet extends StatefulWidget {
  const ProductInitialStockBottomSheet({
    super.key,
    required this.storeId,
    required this.productsApi,
    required this.localPrefs,
    required this.productDraft,
    this.catalogInvalidationBus,
    this.shellOnline = true,
  });

  final String storeId;
  final ProductsApi productsApi;
  final LocalPrefs localPrefs;
  final CatalogProduct productDraft;
  final CatalogInvalidationBus? catalogInvalidationBus;

  /// Si es `false`, encola sin esperar timeout de red (mismo flujo que error de transporte).
  final bool shellOnline;

  @override
  State<ProductInitialStockBottomSheet> createState() =>
      _ProductInitialStockBottomSheetState();
}

class _ProductInitialStockBottomSheetState
    extends State<ProductInitialStockBottomSheet> {
  static const _defaultReason = 'Inventario inicial';

  final _quantity = TextEditingController();
  final _reason = TextEditingController(text: _defaultReason);
  final _unitCost = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Al abrir el flujo; mismo valor en reintentos hasta 200 o cancelar.
  late String _idempotencyKey;

  /// Idempotencia del movimiento `initialStock` (no sustituye la cabecera).
  String? _initialStockOpId;

  /// Cuerpo canónico del último intento (misma clave + mismo JSON en reintentos).
  String? _sentCanon;

  @override
  void initState() {
    super.initState();
    _idempotencyKey = const Uuid().v4();
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
      setState(() => _error = 'Indicá un motivo (auditoría).');
      return;
    }

    final cost = _unitCost.text.trim();
    String? unitCostFunctional;
    if (cost.isNotEmpty) {
      if (!_decimalPositive.hasMatch(cost)) {
        setState(
          () => _error = 'Costo unitario (func.): número decimal válido o vacío.',
        );
        return;
      }
      unitCostFunctional = cost;
    }

    _initialStockOpId ??= ClientMutationId.newId();
    var body = ProductsApi.buildWithStockBody(
      product: widget.productDraft,
      quantity: qty,
      reason: reason,
      initialStockOpId: _initialStockOpId!,
      unitCostFunctional: unitCostFunctional,
    );
    var canon = ProductsApi.canonicalBodyJson(body);

    if (_sentCanon != null && canon != _sentCanon) {
      _idempotencyKey = const Uuid().v4();
      _initialStockOpId = ClientMutationId.newId();
      body = ProductsApi.buildWithStockBody(
        product: widget.productDraft,
        quantity: qty,
        reason: reason,
        initialStockOpId: _initialStockOpId!,
        unitCostFunctional: unitCostFunctional,
      );
      canon = ProductsApi.canonicalBodyJson(body);
    }

    _sentCanon = canon;

    if (!widget.shellOnline) {
      setState(() => _loading = true);
      try {
        await _persistOfflineCreateWithStock(body);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final res = await widget.productsApi.createProductWithStock(
        widget.storeId,
        body,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      widget.catalogInvalidationBus?.invalidateFromLocalMutation(
        productIds: {res.product.id},
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Producto creado · SKU ${res.product.sku} · stock cargado'),
        ),
      );
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.statusCode == 409) {
        setState(() {
          _error =
              'La clave de idempotencia ya se usó con otros datos. Se generó una '
              'nueva clave: revisá los valores y volvé a enviar.';
          _idempotencyKey = const Uuid().v4();
          _sentCanon = null;
          _initialStockOpId = null;
        });
        return;
      }
      if (e.isLikelyTransportFailure) {
        await _persistOfflineCreateWithStock(body);
        return;
      }
      setState(() => _error = e.userMessageForSupport);
    } catch (e) {
      if (!mounted) return;
      if (shouldTreatAsOfflineQueueable(e)) {
        await _persistOfflineCreateWithStock(body);
        return;
      }
      setState(
        () => _error = e is ApiError
            ? e.userMessageForSupport
            : 'No se pudo guardar. Verificá la conexión e intentá de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persistOfflineCreateWithStock(Map<String, dynamic> body) async {
    final localId = 'local_${ClientMutationId.newId()}';
    final pending = await widget.localPrefs.loadPendingCatalogMutations();
    pending.add(
      PendingCatalogMutationEntry(
        opId: ClientMutationId.newId(),
        storeId: widget.storeId,
        type: PendingCatalogMutationEntry.typeCreateWithStock,
        createdAtIso: DateTime.now().toUtc().toIso8601String(),
        localTempId: localId,
        idempotencyKey: _idempotencyKey,
        body: body,
      ),
    );
    await widget.localPrefs.savePendingCatalogMutations(pending);
    final cached = await widget.localPrefs.loadCatalogProductsCache();
    cached.add(
      CatalogProduct(
        id: localId,
        sku: widget.productDraft.sku.isEmpty ? 'PENDIENTE' : widget.productDraft.sku,
        name: widget.productDraft.name,
        barcode: widget.productDraft.barcode,
        description: widget.productDraft.description,
        type: widget.productDraft.type,
        price: widget.productDraft.price,
        cost: widget.productDraft.cost,
        currency: widget.productDraft.currency,
        active: true,
        unit: widget.productDraft.unit,
        supplierId: widget.productDraft.supplierId,
        pricingMode: widget.productDraft.pricingMode,
        marginPercentOverride: widget.productDraft.marginPercentOverride,
        imageUrl: widget.productDraft.imageUrl,
      ),
    );
    await widget.localPrefs.saveCatalogProductsCache(cached);
    widget.catalogInvalidationBus?.invalidateFromLocalMutation(
      productIds: {localId},
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sin conexión: producto+stock guardado en cola.'),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Stock inicial',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            widget.productDraft.name,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (_sentCanon != null) ...[
            const SizedBox(height: 8),
            Text(
              'Reintentos usan la misma Idempotency-Key y el mismo cuerpo. Si cambiás '
              'cantidad u otros datos, la app genera clave y opId nuevos.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _quantity,
            decoration: const InputDecoration(
              labelText: 'Cantidad en depósito',
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
              border: OutlineInputBorder(),
            ),
            enabled: !_loading,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _unitCost,
            decoration: const InputDecoration(
              labelText: 'Costo unitario funcional (opcional)',
              helperText: 'Vacío → usa el costo del producto',
              border: OutlineInputBorder(),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !_loading,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton(
                onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Crear con stock'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
