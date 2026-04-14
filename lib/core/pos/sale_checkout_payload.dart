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
    List<Map<String, dynamic>>? payments,
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
    final effectiveDate =
        fxPair == null || func.toUpperCase() == doc.toUpperCase()
        ? _todayYyyyMmDd()
        : fxPair.rate.effectiveDate.trim().isEmpty
        ? _todayYyyyMmDd()
        : fxPair.rate.effectiveDate.trim();

    final fxSnapshot = <String, dynamic>{
      'baseCurrencyCode': func,
      'quoteCurrencyCode': doc,
      'rateQuotePerBase': rateForSnapshot,
      'effectiveDate': effectiveDate.length >= 10
          ? effectiveDate.substring(0, 10)
          : effectiveDate,
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
              'productId': l.productId.toString(),
              'quantity': l.quantity.toString(),
              'price': l.documentUnitPrice.toString(),
              'discount': '0',
            },
          )
          .toList(),
      'fxSnapshot': fxSnapshot,
      if (payments != null && payments.isNotEmpty)
        'payments': _coercePaymentsForJson(payments),
    };
  }

  /// `sync/push` y validadores estrictos del backend exigen strings en JSON para
  /// cantidades/importes; al rehidratar la cola desde prefs, `jsonDecode` puede
  /// dejar `int`/`double`.
  static String _scalarToJsonString(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num) {
      if (v is double && v == v.roundToDouble()) {
        return v.round().toString();
      }
      return v.toString();
    }
    return v.toString();
  }

  static Map<String, dynamic> _stringifyFxSnapshotMap(Map<String, dynamic> fx) {
    final out = <String, dynamic>{};
    for (final e in fx.entries) {
      out[e.key] = _scalarToJsonString(e.value);
    }
    return out;
  }

  static List<Map<String, dynamic>> _coercePaymentsForJson(
    List<Map<String, dynamic>> payments,
  ) {
    return payments.map((raw) {
      final p = Map<String, dynamic>.from(raw);
      p['method'] = _scalarToJsonString(p['method']);
      p['amount'] = _scalarToJsonString(p['amount']);
      p['currencyCode'] = _scalarToJsonString(p['currencyCode']);
      final nested = p['fxSnapshot'];
      if (nested is Map) {
        p['fxSnapshot'] = _stringifyFxSnapshotMap(
          Map<String, dynamic>.from(nested),
        );
      }
      return p;
    }).toList();
  }

  /// Normaliza `payload.sale` antes de enviarlo en `POST /sync/push`.
  static Map<String, dynamic> coerceSalePayloadForSyncPush(
    Map<String, dynamic> sale,
  ) {
    final out = Map<String, dynamic>.from(sale);
    if (out['id'] != null) {
      out['id'] = _scalarToJsonString(out['id']);
    }
    out['storeId'] = _scalarToJsonString(out['storeId']);
    out['documentCurrencyCode'] = _scalarToJsonString(
      out['documentCurrencyCode'],
    );
    out['deviceId'] = _scalarToJsonString(out['deviceId']);
    out['appVersion'] = _scalarToJsonString(out['appVersion']);

    final lines = out['lines'];
    if (lines is List) {
      out['lines'] = lines.map((e) {
        if (e is! Map) return e;
        final m = Map<String, dynamic>.from(e);
        m['productId'] = _scalarToJsonString(m['productId']);
        m['quantity'] = _scalarToJsonString(m['quantity']);
        m['price'] = _scalarToJsonString(m['price']);
        if (m.containsKey('discount')) {
          m['discount'] = _scalarToJsonString(m['discount']);
        }
        return m;
      }).toList();
    }

    final fx = out['fxSnapshot'];
    if (fx is Map) {
      out['fxSnapshot'] = _stringifyFxSnapshotMap(
        Map<String, dynamic>.from(fx),
      );
    }

    final pays = out['payments'];
    if (pays is List) {
      out['payments'] = pays.map((p) {
        if (p is! Map) return p;
        return _coercePaymentsForJson([
          Map<String, dynamic>.from(p),
        ]).first;
      }).toList();
    }

    return out;
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
    final sale = <String, dynamic>{
      if (restBody['id'] != null && '${restBody['id']}'.isNotEmpty)
        'id': restBody['id'],
      'storeId': storeId.trim(),
      'documentCurrencyCode': restBody['documentCurrencyCode'],
      'deviceId': restBody['deviceId'],
      'lines': restBody['lines'],
      'fxSnapshot': fx,
      if (restBody['payments'] is List) 'payments': restBody['payments'],
    };
    return coerceSalePayloadForSyncPush(sale);
  }

  static String _todayYyyyMmDd() {
    final n = DateTime.now().toUtc();
    final y = n.year.toString().padLeft(4, '0');
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
