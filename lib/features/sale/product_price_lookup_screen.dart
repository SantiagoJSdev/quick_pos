import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/products_api.dart';
import '../../core/models/catalog_product.dart';
import 'barcode_scanner_screen.dart';
import 'pos_sale_ui_tokens.dart';

/// Consulta rápida de precio de lista (catálogo) sin agregar al ticket.
class ProductPriceLookupScreen extends StatefulWidget {
  const ProductPriceLookupScreen({
    super.key,
    required this.storeId,
    required this.productsApi,
  });

  final String storeId;
  final ProductsApi productsApi;

  @override
  State<ProductPriceLookupScreen> createState() =>
      _ProductPriceLookupScreenState();
}

class _ProductPriceLookupScreenState extends State<ProductPriceLookupScreen> {
  final _search = TextEditingController();
  List<CatalogProduct> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _load();
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
    final code = await BarcodeScannerScreen.open(context);
    if (!mounted || code == null || code.isEmpty) return;
    setState(() => _search.text = code);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.productsApi.listProducts(
        widget.storeId,
        includeInactive: false,
      );
      if (!mounted) return;
      setState(() {
        _all = list.where((p) => p.active).toList();
        _loading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessageForSupport;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
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
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                style: const TextStyle(color: PosSaleUi.text),
                cursorColor: PosSaleUi.primary,
                decoration: InputDecoration(
                  hintText: 'Nombre, SKU o código de barras…',
                  hintStyle: const TextStyle(color: PosSaleUi.textFaint),
                  prefixIcon:
                      const Icon(Icons.search, color: PosSaleUi.textMuted),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.qr_code_scanner,
                        color: PosSaleUi.primary),
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
                    borderSide:
                        const BorderSide(color: PosSaleUi.primary, width: 1.5),
                  ),
                ),
                autocorrect: false,
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: PosSaleUi.primary),
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
                                  onPressed: _load,
                                  child: const Text('Reintentar'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: PosSaleUi.primary,
                          onRefresh: _load,
                          child: _filtered.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
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
                                                if (bc != null &&
                                                    bc.isNotEmpty)
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
