import '../models/currency_ref.dart';

/// Respuesta de `GET /api/v1/stores/:storeId/business-settings`.
class BusinessSettings {
  const BusinessSettings({
    required this.id,
    required this.storeId,
    required this.functionalCurrency,
    required this.defaultSaleDocCurrency,
    required this.storeName,
    this.storeType,
    this.defaultMarginPercent,
    this.allowNegativeStockAtPos = true,
    this.warnOnNegativeStock = true,
    this.blockRestrictedProductsWithoutStock = true,
    this.requireSuccessfulSyncAtClose = false,
  });

  final String id;
  final String storeId;
  final CurrencyRef functionalCurrency;
  final CurrencyRef? defaultSaleDocCurrency;
  final String storeName;
  final String? storeType;

  /// % margen por defecto de la tienda (`GET/PATCH .../business-settings`, M7).
  final String? defaultMarginPercent;

  /// B1 — permitir vender aunque el stock local/servidor quede negativo.
  final bool allowNegativeStockAtPos;

  /// B1 — mostrar modal de incidencia al quedar negativo.
  final bool warnOnNegativeStock;

  /// B1 — productos restringidos sin stock: bloquear o pedir PIN en app.
  final bool blockRestrictedProductsWithoutStock;

  /// B2 — soft warning al cerrar caja si queda cola (no hard-block).
  final bool requireSuccessfulSyncAtClose;

  static BusinessSettings fromJson(Map<String, dynamic> json) {
    final store = json['store'] as Map<String, dynamic>?;
    final func = CurrencyRef.fromJson(
      json['functionalCurrency'] as Map<String, dynamic>?,
    );
    if (func == null) {
      throw const FormatException('functionalCurrency missing');
    }
    return BusinessSettings(
      id: json['id'] as String? ?? '',
      storeId: json['storeId'] as String? ?? '',
      functionalCurrency: func,
      defaultSaleDocCurrency: CurrencyRef.fromJson(
        json['defaultSaleDocCurrency'] as Map<String, dynamic>?,
      ),
      storeName: store?['name'] as String? ?? '(sin nombre)',
      storeType: store?['type'] as String?,
      defaultMarginPercent: _optString(json['defaultMarginPercent']),
      allowNegativeStockAtPos: _optBool(
        json['allowNegativeStockAtPos'],
        defaultValue: true,
      ),
      warnOnNegativeStock: _optBool(
        json['warnOnNegativeStock'],
        defaultValue: true,
      ),
      blockRestrictedProductsWithoutStock: _optBool(
        json['blockRestrictedProductsWithoutStock'],
        defaultValue: true,
      ),
      requireSuccessfulSyncAtClose: _optBool(
        json['requireSuccessfulSyncAtClose'],
        defaultValue: false,
      ),
    );
  }

  static String? _optString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool _optBool(dynamic v, {required bool defaultValue}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    final s = v.toString().trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
    return defaultValue;
  }

  /// Shape que espera [LocalPrefs.saveBusinessSettingsCache].
  Map<String, dynamic> toPrefsJson() => {
        'id': id,
        'storeId': storeId,
        'defaultMarginPercent': defaultMarginPercent,
        'allowNegativeStockAtPos': allowNegativeStockAtPos,
        'warnOnNegativeStock': warnOnNegativeStock,
        'blockRestrictedProductsWithoutStock':
            blockRestrictedProductsWithoutStock,
        'requireSuccessfulSyncAtClose': requireSuccessfulSyncAtClose,
        'functionalCurrency': {
          'code': functionalCurrency.code,
          'name': functionalCurrency.name,
        },
        'defaultSaleDocCurrency': defaultSaleDocCurrency == null
            ? null
            : {
                'code': defaultSaleDocCurrency!.code,
                'name': defaultSaleDocCurrency!.name,
              },
        'store': {'name': storeName, 'type': storeType},
      };
}
