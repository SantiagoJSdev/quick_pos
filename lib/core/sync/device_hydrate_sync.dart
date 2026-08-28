import '../api/exchange_rates_api.dart';
import '../api/inventory_api.dart';
import '../api/payment_methods_api.dart';
import '../api/products_api.dart';
import '../api/stores_api.dart';
import '../api/sync_api.dart';
import '../cash/cash_session_service.dart';
import '../catalog/catalog_invalidation_bus.dart';
import '../catalog/catalog_offline_sync.dart';
import '../photos/product_photo_upload_sync.dart';
import '../storage/local_prefs.dart';
import 'pending_sale_entry.dart';
import 'sync_cycle.dart';

typedef DeviceHydrateCallback = Future<DeviceHydrateResult> Function({
  void Function(String step)? onProgress,
  bool requireEmptyQueue,
});

/// Resultado de enviar cola + bajar productos, stock y tasa a este teléfono.
class DeviceHydrateResult {
  const DeviceHydrateResult({
    required this.ok,
    required this.userMessage,
    this.failedStep,
    this.flushedAll = false,
    this.downloadedOk = false,
    this.productCount = 0,
    this.inventoryCount = 0,
    this.paymentMethodCount = 0,
    this.flushedOps = 0,
    this.remainingOps = 0,
    this.fxLabel,
  });

  final bool ok;
  final String userMessage;
  final String? failedStep;
  final bool flushedAll;
  final bool downloadedOk;
  final int productCount;
  final int inventoryCount;
  final int paymentMethodCount;
  final int flushedOps;
  final int remainingOps;
  final String? fxLabel;
}

/// Flush + GET /products + GET /inventory + métodos de pago + settings/FX.
///
/// Si [requireEmptyQueue] (cierre de caja): `ok` solo si no queda nada pendiente
/// **y** se guardó el snapshot. Si no: se baja igual el stock, y `ok` exige
/// productos+stock+tasa; si queda cola, `ok` es false con mensaje claro.
Future<DeviceHydrateResult> hydrateDeviceFromServer({
  required String storeId,
  required LocalPrefs prefs,
  required SyncApi syncApi,
  required ProductsApi productsApi,
  required InventoryApi inventoryApi,
  required StoresApi storesApi,
  required ExchangeRatesApi exchangeRatesApi,
  PaymentMethodsApi? paymentMethodsApi,
  required String deviceId,
  required String appVersion,
  CatalogInvalidationBus? catalogInvalidation,
  CashSessionService? cashSessions,
  ProductPhotoUploader? photoUploader,
  void Function(String step)? onProgress,
  bool requireEmptyQueue = false,
}) async {
  void step(String s) => onProgress?.call(s);

  try {
    step('Comprobando servidor…');
    final settings = await storesApi.getBusinessSettings(storeId);

    step('Enviando operaciones pendientes…');
    if (cashSessions != null) {
      try {
        await cashSessions.tryTransmitPendingClose(
          storeId: storeId,
          online: true,
        );
      } catch (_) {}
      try {
        await cashSessions.tryTransmitPendingOpen(
          storeId: storeId,
          online: true,
        );
      } catch (_) {}
    }

    final cycle = await runSyncCycle(
      storeId: storeId,
      prefs: prefs,
      syncApi: syncApi,
      deviceId: deviceId,
      appVersion: appVersion,
      catalogInvalidation: catalogInvalidation,
      doPull: true,
      doFlush: true,
    );

    await flushPendingCatalogMutations(
      storeId: storeId,
      prefs: prefs,
      productsApi: productsApi,
      catalogInvalidation: catalogInvalidation,
    );

    if (photoUploader != null) {
      await flushPendingProductPhotoUploads(
        storeId: storeId,
        prefs: prefs,
        uploader: photoUploader,
      );
    }

    final remaining = await prefs.countPendingSyncOpsForStore(storeId);
    final flushedAll = remaining == 0;

    if (requireEmptyQueue && !flushedAll) {
      return DeviceHydrateResult(
        ok: false,
        flushedAll: false,
        downloadedOk: false,
        flushedOps: cycle.flush.removedCount,
        remainingOps: remaining,
        failedStep: 'cola',
        userMessage:
            'No se puede continuar: quedan $remaining operación(es) sin enviar. '
            'Revisá la red y reintentá.',
      );
    }

    step('Bajando productos y precios…');
    final products = await productsApi.listProducts(
      storeId,
      includeInactive: false,
    );

    step('Bajando stock…');
    final inventory = await inventoryApi.listInventory(storeId);

    step('Bajando métodos de pago…');
    var paymentMethodCount = 0;
    if (paymentMethodsApi != null) {
      final methods = await paymentMethodsApi.listActive(storeId);
      paymentMethodCount = methods.length;
      await prefs.savePaymentMethodsCache(storeId, methods);
    }

    step('Actualizando tasa…');
    await prefs.saveBusinessSettingsCache(storeId, settings.toPrefsJson());
    var fxLabel = 'misma moneda';
    final func = settings.functionalCurrency.code.trim();
    final doc = (settings.defaultSaleDocCurrency?.code ?? func).trim();
    if (func.toUpperCase() != doc.toUpperCase()) {
      await _refreshFxPair(
        storeId: storeId,
        prefs: prefs,
        api: exchangeRatesApi,
        functionalCode: func,
        documentCode: doc,
      );
      fxLabel = 'tasa $func→$doc';
    }

    step('Guardando en este teléfono…');
    await prefs.saveCatalogProductsCache(products);
    await prefs.saveInventoryCache(storeId, inventory);
    await _reapplyPendingSaleDecrements(storeId: storeId, prefs: prefs);

    catalogInvalidation?.invalidateFromLocalMutation();
    await prefs.markLastSuccessfulSyncNow();

    final downloadedOk = true;
    final parts = <String>[
      '${products.length} productos',
      '${inventory.length} stock',
      fxLabel,
    ];
    if (paymentMethodCount > 0) {
      parts.add('$paymentMethodCount métodos de pago');
    }
    if (cycle.flush.removedCount > 0) {
      parts.add('${cycle.flush.removedCount} op. enviadas');
    }
    if (!flushedAll) {
      parts.add('quedan $remaining sin enviar');
    }
    if (cycle.pullError != null && cycle.pullError!.trim().isNotEmpty) {
      parts.add('aviso pull: ${cycle.pullError}');
    }

    return DeviceHydrateResult(
      ok: flushedAll,
      flushedAll: flushedAll,
      downloadedOk: downloadedOk,
      productCount: products.length,
      inventoryCount: inventory.length,
      paymentMethodCount: paymentMethodCount,
      flushedOps: cycle.flush.removedCount,
      remainingOps: remaining,
      fxLabel: fxLabel,
      userMessage: flushedAll
          ? 'Sincronizado: se envió todo y se actualizaron ${parts.join(', ')}.'
          : 'Se actualizaron productos y stock, pero quedan $remaining '
              'operación(es) sin enviar. Reintentá Sincronizar.',
    );
  } catch (e) {
    return DeviceHydrateResult(
      ok: false,
      flushedAll: false,
      downloadedOk: false,
      failedStep: 'red',
      userMessage:
          'Sincronización incompleta. Este teléfono no se actualizó.\n$e',
    );
  }
}

Future<void> _refreshFxPair({
  required String storeId,
  required LocalPrefs prefs,
  required ExchangeRatesApi api,
  required String functionalCode,
  required String documentCode,
}) async {
  final func = functionalCode.trim();
  final doc = documentCode.trim();
  Object? lastError;
  for (final pair in [(func, doc), (doc, func)]) {
    try {
      final rate = await api.getLatest(
        storeId,
        baseCurrencyCode: pair.$1,
        quoteCurrencyCode: pair.$2,
      );
      await prefs.saveLatestRateCache(
        storeId: storeId,
        baseCurrencyCode: pair.$1,
        quoteCurrencyCode: pair.$2,
        effectiveOn: null,
        rate: rate,
      );
      await prefs.syncPosFxPairCacheFromFetchedRate(
        storeId: storeId,
        fetchedBase: pair.$1,
        fetchedQuote: pair.$2,
        rate: rate,
      );
      return;
    } catch (e) {
      lastError = e;
    }
  }
  throw StateError(
    'No se pudo actualizar la tasa ($func / $doc): $lastError',
  );
}

/// Tras pisar stock con el servidor, restar ventas de este teléfono aún en cola.
Future<void> _reapplyPendingSaleDecrements({
  required String storeId,
  required LocalPrefs prefs,
}) async {
  final pending = await prefs.loadPendingSales();
  final sold = <String, double>{};
  for (final e in pending) {
    if (e.storeId != storeId) continue;
    _accumulateSold(sold, e);
  }
  if (sold.isEmpty) return;
  await prefs.applyLocalInventoryDecrements(
    storeId: storeId,
    soldByProductId: sold,
  );
}

void _accumulateSold(Map<String, double> sold, PendingSaleEntry e) {
  final lines = e.sale['lines'];
  if (lines is! List) return;
  for (final raw in lines) {
    if (raw is! Map) continue;
    final id = raw['productId']?.toString().trim() ?? '';
    final q = double.tryParse(raw['quantity']?.toString().trim() ?? '') ?? 0;
    if (id.isEmpty || q == 0) continue;
    sold[id] = (sold[id] ?? 0) + q;
  }
}
