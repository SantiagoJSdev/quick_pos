import 'dart:convert';

import '../models/catalog_product.dart';

/// Cuerpo de `POST /api/v1/products-with-stock` + JSON canónico para idempotencia.
///
/// `Idempotency-Key` (cabecera) es independiente de `initialStock.opId` (movimiento).
/// Ver `docs/FRONTEND_INTEGRATION_CONTEXT.md` §13.6b (copiar desde backend si cambia).
class ProductWithStockPayload {
  ProductWithStockPayload._();

  static Map<String, dynamic> build({
    required CatalogProduct product,
    required String quantity,
    required String reason,
    required String initialStockOpId,
    String? unitCostFunctional,
  }) {
    final initialStock = <String, dynamic>{
      'quantity': quantity.trim(),
      'reason': reason.trim(),
      'opId': initialStockOpId.trim(),
    };
    final u = unitCostFunctional?.trim();
    if (u != null && u.isNotEmpty) {
      initialStock['unitCostFunctional'] = u;
    }
    // Mismo shape que `POST /products` en la raíz + `initialStock` (§13.6b backend).
    final body = Map<String, dynamic>.from(product.toCreateBody());
    body['initialStock'] = initialStock;
    return body;
  }

  /// Misma serialización que el body enviado al API (para comparar reintentos).
  static String canonicalJson(Map<String, dynamic> body) => jsonEncode(body);
}
