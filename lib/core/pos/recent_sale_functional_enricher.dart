import '../models/recent_sale_ticket.dart';
import '../storage/local_prefs.dart';
import 'money_string_math.dart';
import 'sale_checkout_payload.dart';

/// Completa `totalFunctional` en tickets locales que solo tienen monto documento.
class RecentSaleFunctionalEnricher {
  RecentSaleFunctionalEnricher._();

  /// Devuelve la lista enriquecida. Si hubo cambios, los persiste en prefs.
  static Future<List<RecentSaleTicket>> enrichForStore({
    required LocalPrefs prefs,
    required String storeId,
    required List<RecentSaleTicket> tickets,
  }) async {
    if (tickets.isEmpty) return tickets;

    final settings = await prefs.loadBusinessSettingsCache(storeId);
    final funcCode = (settings?.functionalCurrency.code.trim().isNotEmpty == true)
        ? settings!.functionalCurrency.code.trim()
        : 'USD';

    final pending = await prefs.loadPendingSales();
    final saleById = <String, Map<String, dynamic>>{};
    for (final e in pending) {
      if (e.storeId.trim() != storeId.trim()) continue;
      final id = e.sale['id']?.toString().trim() ?? '';
      if (id.isEmpty) continue;
      saleById[id] = e.sale;
    }

    final fxCache = <String, SaleFxPair?>{};
    Future<SaleFxPair?> pairFor(String docCode) async {
      final key = '${funcCode.toUpperCase()}|${docCode.toUpperCase()}';
      if (fxCache.containsKey(key)) return fxCache[key];
      final p = await prefs.loadPosFxPairCache(
        storeId: storeId,
        functionalCode: funcCode,
        documentCode: docCode,
      );
      fxCache[key] = p;
      return p;
    }

    var changed = false;
    final enriched = <RecentSaleTicket>[];
    for (final t in tickets) {
      final existing = t.totalFunctional?.trim();
      if (existing != null && existing.isNotEmpty) {
        enriched.add(
          t.functionalCurrencyCode == null ||
                  t.functionalCurrencyCode!.trim().isEmpty
              ? t.copyWith(functionalCurrencyCode: funcCode)
              : t,
        );
        if (t.functionalCurrencyCode == null ||
            t.functionalCurrencyCode!.trim().isEmpty) {
          changed = true;
        }
        continue;
      }

      String? tf;
      var fc = funcCode;

      final sale = saleById[t.saleId];
      if (sale != null) {
        final fromSale = functionalFromSalePayload(
          sale: sale,
          totalDocument: t.totalDocument,
        );
        if (fromSale != null) {
          tf = fromSale.$1;
          fc = fromSale.$2;
        }
      }

      if (tf == null || tf.isEmpty) {
        final pair = await pairFor(t.documentCurrencyCode);
        tf = documentToFunctional(
          totalDocument: t.totalDocument,
          documentCurrencyCode: t.documentCurrencyCode,
          functionalCurrencyCode: funcCode,
          pair: pair,
        );
        fc = funcCode;
      }

      if (tf != null && tf.isNotEmpty) {
        changed = true;
        enriched.add(
          t.copyWith(totalFunctional: tf, functionalCurrencyCode: fc),
        );
      } else {
        enriched.add(t);
      }
    }

    if (changed) {
      final all = await prefs.loadRecentSaleTickets();
      final byId = {for (final t in enriched) t.saleId: t};
      final merged = all.map((t) => byId[t.saleId] ?? t).toList();
      await prefs.saveRecentSaleTickets(merged);
    }

    return enriched;
  }

  /// `(totalFunctional, functionalCurrencyCode)` desde payload de cola.
  static (String, String)? functionalFromSalePayload({
    required Map<String, dynamic> sale,
    required String totalDocument,
  }) {
    final doc = (sale['documentCurrencyCode']?.toString() ?? '').trim();
    final fx = sale['fxSnapshot'];
    if (fx is! Map) return null;
    final base = (fx['baseCurrencyCode']?.toString() ?? '').trim();
    final rate = (fx['rateQuotePerBase']?.toString() ?? '').trim();
    if (base.isEmpty) return null;

    if (doc.isNotEmpty && base.toUpperCase() == doc.toUpperCase()) {
      return (totalDocument.trim(), base);
    }
    if (rate.isEmpty) return null;
    final tf = MoneyStringMath.divide(totalDocument, rate, fractionDigits: 2);
    return (tf, base);
  }

  static String? documentToFunctional({
    required String totalDocument,
    required String documentCurrencyCode,
    required String functionalCurrencyCode,
    required SaleFxPair? pair,
  }) {
    final doc = documentCurrencyCode.trim();
    final func = functionalCurrencyCode.trim();
    final td = totalDocument.trim();
    if (td.isEmpty || func.isEmpty || doc.isEmpty) return null;
    if (func.toUpperCase() == doc.toUpperCase()) return td;
    if (pair == null) return null;
    final rate = SaleCheckoutPayload.rateFunctionalPerDocumentSnapshot(
      functionalCode: func,
      documentCode: doc,
      pair: pair,
    );
    return MoneyStringMath.divide(td, rate, fractionDigits: 2);
  }
}
