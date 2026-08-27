import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/products_api.dart';
import '../../core/models/catalog_product.dart';
import '../../core/storage/local_prefs.dart';
import 'barcode_scanner_screen.dart';
import 'pos_sale_ui_tokens.dart';

/// Consulta rápida de precio de lista (catálogo) sin agregar al ticket.
/// Solo cache local; actualizá el catálogo con Sincronizar en Inicio/POS.
class ProductPriceLookupScreen extends StatefulWidget {
  const ProductPriceLookupScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
    required this.localPrefs,
  });

  final String storeId;
  final ProductsApi productsApi;
  final LocalPrefs localPrefs;

  @override
  State<ProductPriceLookupScreen> createState() =>
      _ProductPriceLookupScreenState();
}

class _ProductPriceLookupScreenState extends State<ProductPriceLookupScreen> {
  final _search = TextEditingController();
  List<CatalogProduct> _all = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  bool _fromCacheOnly = false;
  bool _likelyStale = false;
  DateTime? _lastSyncAt;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    unawaited(_reloadFromCache());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _scanSearch() async {
    if (!BarcodeScannerScreen.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El escáner solo está disponible en Android e iOS.'),
        ),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final code = await BarcodeScannerScreen.open(context);
    if (!mounted || code == null || code.isEmpty) return;
    setState(() => _search.text = code);
  }

  Future<void> _refreshStaleFlags() async {
    final at = await widget.localPrefs.loadLastSuccessfulSyncAt();
    final stale = await widget.localPrefs.isCatalogLikelyStale();
    if (!mounted) return;
    setState(() {
      _lastSyncAt = at;
      _likelyStale = stale;
    });
  }

  Future<void> _reloadFromCache({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _refreshing = true);
    }
    final cached = await widget.localPrefs.loadCatalogProductsCache();
    if (!mounted) return;
    if (cached.isNotEmpty) {
      setState(() {
        _all = cached.where((p) => p.active).toList();
        _loading = false;
        _refreshing = false;
        _error = null;
        _fromCacheOnly = true;
      });
      await _refreshStaleFlags();
      return;
    }
    setState(() {
      _all = [];
      _loading = false;
      _refreshing = false;
      _error =
          'Sin catálogo en este dispositivo. Tocá Sincronizar en Inicio.';
    });
  }

  List<CatalogProduct> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _all;
    return _all.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q) ||
          (p.barcode?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  String? get _staleBannerText {
    if (_all.isEmpty) return null;
    if (_fromCacheOnly || _likelyStale) {
      final when = _lastSyncAt;
      final whenLabel = when == null
          ? 'sin sync reciente'
          : 'última sync ${when.hour.toString().padLeft(2, '0')}:'
                '${when.minute.toString().padLeft(2, '0')}';
      return 'Precios desde cache local ($whenLabel). '
          'Deslizá para actualizar o usá Sincronizar en Inicio.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final banner = _staleBannerText;
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: PosSaleUi.bg,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          backgroundColor: PosSaleUi.surface,
          foregroundColor: PosSaleUi.text,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Buscar precio'),
          actions: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: PosSaleUi.primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (banner != null)
              Material(
                color: Colors.orange.withValues(alpha: 0.12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    banner,
                    style: const TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                style: const TextStyle(color: PosSaleUi.text),
                cursorColor: PosSaleUi.primary,
                decoration: InputDecoration(
                  hintText: 'Nombre, SKU o código de barras…',
                  hintStyle: const TextStyle(color: PosSaleUi.textFaint),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: PosSaleUi.textMuted,
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.qr_code_scanner,
                      color: PosSaleUi.primary,
                    ),
                    tooltip: 'Escanear código de barras o QR del producto',
                    onPressed: _loading ? null : _scanSearch,
                  ),
                  filled: true,
                  fillColor: PosSaleUi.surface3,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: PosSaleUi.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: PosSaleUi.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: PosSaleUi.primary,
                      width: 1.5,
                    ),
                  ),
                ),
                autocorrect: false,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: PosSaleUi.primary,
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: PosSaleUi.text),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: () =>
                                  _reloadFromCache(showSpinner: true),
                              child: const Text('Reintentar'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      color: PosSaleUi.primary,
                      onRefresh: () => _reloadFromCache(showSpinner: false),
                      child: _filtered.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                SizedBox(height: 48),
                                Text(
                                  'Sin resultados',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: PosSaleUi.textMuted),
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: _filtered.length,
                              separatorBuilder: (context, i) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final p = _filtered[i];
                                final bc = p.barcode?.trim();
                                return Material(
                                  color: PosSaleUi.surface2,
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            color: PosSaleUi.text,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          [
                                            'SKU ${p.sku}',
                                            if (bc != null && bc.isNotEmpty)
                                              'EAN $bc',
                                          ].join(' · '),
                                          style: const TextStyle(
                                            color: PosSaleUi.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          '${p.price} ${p.currency}',
                                          style: const TextStyle(
                                            color: PosSaleUi.gold,
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
