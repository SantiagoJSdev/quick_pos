import 'package:flutter/foundation.dart';

/// Señal de que el catálogo en memoria / listas en pantalla pueden estar obsoletas.
///
/// **Por qué no SQLite del catálogo aquí:** el contrato ya expone `GET /products` con
/// el shape completo; duplicar filas en SQLite obliga a migraciones y a alinear cada
/// campo con el pull parcial (`fields`). La práctica modular es: **pull = evento**,
/// **REST = materialización** (refetch). Más adelante se puede sustituir el refetch
/// por lectura de caché local sin cambiar el bus.
class CatalogInvalidationBus extends ChangeNotifier {
  int _generation = 0;
  Set<String> _lastTouchedProductIds = {};

  /// Monótono; útil para depuración o comparar “ya procesé este tick”.
  int get generation => _generation;

  /// Últimos `productId` vistos en un pull `PRODUCT_*` (puede estar vacío si solo hubo invalidación global).
  Set<String> get lastTouchedProductIds =>
      Set.unmodifiable(_lastTouchedProductIds);

  /// Llamado tras aplicar lógicamente ops de pull que afectan catálogo.
  void invalidateFromPull({Set<String>? productIds}) {
    _generation++;
    _lastTouchedProductIds = productIds != null
        ? Set<String>.from(productIds)
        : {};
    notifyListeners();
  }

  /// Compra local / cola offline: mismos listeners que un pull de catálogo.
  void invalidateFromLocalMutation({Set<String>? productIds}) {
    invalidateFromPull(productIds: productIds);
  }
}
