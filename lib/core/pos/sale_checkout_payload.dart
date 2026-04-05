import '../models/latest_exchange_rate.dart';
import '../models/pos_cart_line.dart';
import 'money_string_math.dart';

/// Par FX cargado: directo `base=funcional`, `quote=documento`, o invertido desde API.
class SaleFxPair {
  const SaleFxPair({required this.rate, required this.inverted});

  final LatestExchangeRate rate;
  final bool inverted;
}

/// Construye el cuerpo de `POST /api/v1/sales` con `fxSnapshot` canónico (funcional → documento).
class SaleCheckoutPayload {
  SaleCheckoutPayload._();

  /// Tasa **1 unidad funcional = N unidades documento** (string decimal).
  static String rateFunctionalPerDocumentSnapshot({
    required String functionalCode,
    required String documentCode,
    required SaleFxPair? pair,
  }) {
    final f = functionalCode.toUpperCase();
    final d = documentCode.toUpperCase();
    if (f == d) return '1';
    if (pair == null) return '1';
    final r = pair.rate;
    if (!pair.inverted) {
      return r.rateQuotePerBase.trim();
    }
    return MoneyStringMath.divide('1', r.rateQuotePerBase, fractionDigits: 8);
  }

  static Map<String, dynamic> build({
    required String documentCurrencyCode,
    required String functionalCurrencyCode,
    required List<PosCartLine> lines,
    required SaleFxPair? fxPair,
    required String deviceId,
    required String appVersion,
    String? clientSaleId,
    String? fxSource,
  }) {
    final doc = documentCurrencyCode.trim();
    final func = functionalCurrencyCode.trim();
    final rateForSnapshot = rateFunctionalPerDocumentSnapshot(
      functionalCode: func,
      documentCode: doc,
      pair: fxPair,
    );
    final effectiveDate = fxPair == null || func.toUpperCase() == doc.toUpperCase()
        ? _todayYyyyMmDd()
        : fxPair.rate.effectiveDate.trim().isEmpty
            ? _todayYyyyMmDd()
            : fxPair.rate.effectiveDate.trim();

    final fxSnapshot = <String, dynamic>{
      'baseCurrencyCode': func,
      'quoteCurrencyCode': doc,
      'rateQuotePerBase': rateForSnapshot,
      'effectiveDate': effectiveDate.length >= 10 ? effectiveDate.substring(0, 10) : effectiveDate,
    };
    if (fxSource != null && fxSource.isNotEmpty) {
      fxSnapshot['fxSource'] = fxSource;
    }

    return <String, dynamic>{
      if (clientSaleId != null && clientSaleId.isNotEmpty) 'id': clientSaleId,
      'documentCurrencyCode': doc,
      'deviceId': deviceId,
      'appVersion': appVersion,
      'lines': lines
          .map(
            (l) => <String, dynamic>{
              'productId': l.productId,
              'quantity': l.quantity.toString(),
              'price': l.documentUnitPrice,
              'discount': '0',
            },
          )
          .toList(),
      'fxSnapshot': fxSnapshot,
    };
  }

  /// `payload.sale` para `POST /api/v1/sync/push` (`SYNC_CONTRACTS.md`), misma forma FX que REST.
  static Map<String, dynamic> syncSaleFromRestBody(
    Map<String, dynamic> restBody,
    String storeId, {
    String? fxSource,
  }) {
    final rawFx = restBody['fxSnapshot'];
    final fx = Map<String, dynamic>.from(rawFx as Map);
    if (fxSource != null && fxSource.isNotEmpty) {
      fx['fxSource'] = fxSource;
    }
    return <String, dynamic>{
      if (restBody['id'] != null && '${restBody['id']}'.isNotEmpty)
        'id': restBody['id'],
      'storeId': storeId.trim(),
      'documentCurrencyCode': restBody['documentCurrencyCode'],
      'deviceId': restBody['deviceId'],
      'lines': restBody['lines'],
      'fxSnapshot': fx,
    };
  }

  static String _todayYyyyMmDd() {
    final n = DateTime.now().toUtc();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
