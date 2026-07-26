import '../models/business_settings.dart';
import '../models/catalog_product.dart';
import '../models/inventory_line.dart';
import '../models/pos_cart_line.dart';

/// Estado de stock mostrado en POS (capa estimada local).
enum PosStockUiStatus {
  exact,
  estimated,
  unverified,
  mayGoNegative,
  restricted,
}

extension PosStockUiStatusLabel on PosStockUiStatus {
  String get labelEs {
    switch (this) {
      case PosStockUiStatus.exact:
        return 'Stock exacto';
      case PosStockUiStatus.estimated:
        return 'Stock estimado';
      case PosStockUiStatus.unverified:
        return 'Sin verificar';
      case PosStockUiStatus.mayGoNegative:
        return 'Puede quedar negativo';
      case PosStockUiStatus.restricted:
        return 'Restringido';
    }
  }
}

class PosStockLineAssessment {
  const PosStockLineAssessment({
    required this.productId,
    required this.productName,
    required this.requestedQty,
    required this.status,
    required this.willGoNegative,
    required this.isRestricted,
    this.availableQty,
  });

  final String productId;
  final String productName;
  final double requestedQty;
  final double? availableQty;
  final PosStockUiStatus status;
  final bool willGoNegative;
  final bool isRestricted;

  String get availableLabel {
    final a = availableQty;
    if (a == null) return '—';
    if (a == a.roundToDouble()) return '${a.round()}';
    return a.toStringAsFixed(3);
  }
}

class PosStockCartAssessment {
  const PosStockCartAssessment({
    required this.lines,
    required this.hasInsufficient,
    required this.hasRestrictedInsufficient,
    required this.hasWarnableNegative,
  });

  final List<PosStockLineAssessment> lines;
  final bool hasInsufficient;
  final bool hasRestrictedInsufficient;
  final bool hasWarnableNegative;
}

double _parseQty(String raw) {
  final t = raw.trim().replaceAll(',', '.');
  return double.tryParse(t) ?? 0;
}

/// Evalúa stock local vs cantidades del ticket.
PosStockCartAssessment assessPosCartStock({
  required List<PosCartLine> cart,
  required List<CatalogProduct> catalog,
  required List<InventoryLine> inventory,
  required BusinessSettings? settings,
  required bool catalogLikelyFresh,
}) {
  final byId = {for (final p in catalog) p.id: p};
  final invById = {for (final l in inventory) l.productId: l};
  final allowNeg = settings?.allowNegativeStockAtPos ?? true;
  final lines = <PosStockLineAssessment>[];

  for (final c in cart) {
    final p = byId[c.productId];
    final restricted = p?.blockSaleWithoutStock == true;
    final req = _parseQty(c.quantity);
    final inv = invById[c.productId];
    final available = inv?.quantityAsDouble;
    final willNeg = available != null && available < req;

    late final PosStockUiStatus status;
    if (restricted && willNeg) {
      status = PosStockUiStatus.restricted;
    } else if (available == null) {
      status = PosStockUiStatus.unverified;
    } else if (willNeg) {
      status = PosStockUiStatus.mayGoNegative;
    } else if (catalogLikelyFresh) {
      status = PosStockUiStatus.exact;
    } else {
      status = PosStockUiStatus.estimated;
    }

    lines.add(
      PosStockLineAssessment(
        productId: c.productId,
        productName: c.name,
        requestedQty: req,
        availableQty: available,
        status: status,
        willGoNegative: willNeg,
        isRestricted: restricted,
      ),
    );
  }

  final insufficient = lines.where((l) => l.willGoNegative).toList();
  final restrictedInsuf = insufficient.where((l) => l.isRestricted).toList();
  final warnable = insufficient.where((l) {
    if (l.isRestricted) return false;
    if (!allowNeg) return false;
    return true;
  }).toList();

  return PosStockCartAssessment(
    lines: lines,
    hasInsufficient: insufficient.isNotEmpty,
    hasRestrictedInsufficient: restrictedInsuf.isNotEmpty,
    hasWarnableNegative: warnable.isNotEmpty,
  );
}
