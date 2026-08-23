import '../models/payment_method.dart';
import 'api_client.dart';

/// `GET /api/v1/payment-methods` — catálogo activo POS.
class PaymentMethodsApi {
  PaymentMethodsApi(this._client);

  final ApiClient _client;

  /// Solo métodos `active` para cobro.
  Future<List<PaymentMethod>> listActive(String storeId) async {
    final json = await _client.getJson('/payment-methods', storeId);
    final raw = json['items'] ?? json;
    if (raw is! List) return const [];
    final out = <PaymentMethod>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final m = PaymentMethod.tryFromJson(Map<String, dynamic>.from(e));
      if (m != null && m.active) out.add(m);
    }
    return out;
  }
}
