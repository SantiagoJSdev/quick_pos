import 'currency_ref.dart';

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
  });

  final String id;
  final String storeId;
  final CurrencyRef functionalCurrency;
  final CurrencyRef? defaultSaleDocCurrency;
  final String storeName;
  final String? storeType;

  /// % margen por defecto de la tienda (`GET/PATCH .../business-settings`, M7).
  final String? defaultMarginPercent;

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
    );
  }

  static String? _optString(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
