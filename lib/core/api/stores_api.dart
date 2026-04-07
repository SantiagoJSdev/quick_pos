import '../models/business_settings.dart';
import 'api_client.dart';

class StoresApi {
  StoresApi(this._client);

  final ApiClient _client;

  Future<BusinessSettings> getBusinessSettings(String storeId) async {
    final json = await _client.getJson(
      '/stores/$storeId/business-settings',
      storeId,
    );
    return BusinessSettings.fromJson(json);
  }

  /// `PATCH /stores/:storeId/business-settings` — p. ej. `defaultMarginPercent` (string 0–999, M7).
  Future<BusinessSettings> patchBusinessSettings(
    String storeId,
    Map<String, dynamic> body,
  ) async {
    final json = await _client.patchJson(
      '/stores/$storeId/business-settings',
      storeId,
      body,
    );
    return BusinessSettings.fromJson(json);
  }

  /// Alta de tienda desde el dispositivo con **UUID generado en el cliente**.
  ///
  /// Contrato documentado: `FRONTEND_INTEGRATION_CONTEXT.md` §13.0 y
  /// `docs/BACKEND_STORE_ONBOARDING.md`. Requiere `STORE_ONBOARDING_ENABLED=1`
  /// en el servidor; si no, los `PUT` responden **403**.
  ///
  /// 1. `PUT /api/v1/stores/{storeId}` — `{ "name", "type": "main"|"branch" }`.
  /// 2. `PUT /api/v1/stores/{storeId}/business-settings` — códigos de moneda.
  /// 3. [getBusinessSettings] para verificar (mismo shape que el GET).
  Future<BusinessSettings> registerNewStore({
    required String storeId,
    required String name,
    required String functionalCurrencyCode,
    required String defaultSaleDocCurrencyCode,
    String type = 'main',
  }) async {
    await _client.putJson(
      '/stores/$storeId',
      storeId,
      {'name': name, 'type': type},
    );
    await _client.putJson(
      '/stores/$storeId/business-settings',
      storeId,
      {
        'functionalCurrencyCode': functionalCurrencyCode,
        'defaultSaleDocCurrencyCode': defaultSaleDocCurrencyCode,
      },
    );
    return getBusinessSettings(storeId);
  }
}
