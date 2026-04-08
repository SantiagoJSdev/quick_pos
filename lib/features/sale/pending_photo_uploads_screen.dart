import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_client.dart';
import '../../core/api/products_api.dart';
import '../../core/api/uploads_api.dart';
import '../../core/photos/product_photo_upload_sync.dart';
import '../../core/photos/pending_product_photo_upload_entry.dart';
import '../../core/storage/local_prefs.dart';
import 'pos_sale_ui_tokens.dart';

class PendingPhotoUploadsScreen extends StatefulWidget {
  const PendingPhotoUploadsScreen({
    super.key,
    required this.storeId,
    required this.localPrefs,
  });

  final String storeId;
  final LocalPrefs localPrefs;

  @override
  State<PendingPhotoUploadsScreen> createState() =>
      _PendingPhotoUploadsScreenState();
}

class _PendingPhotoUploadsScreenState extends State<PendingPhotoUploadsScreen> {
  bool _loading = true;
  bool _retryingNow = false;
  String? _error;
  List<PendingProductPhotoUploadEntry> _rows = const [];
  String _filter = 'ALL';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final all = await widget.localPrefs.loadPendingProductPhotoUploads();
      final mine = all.where((e) => e.storeId == widget.storeId).toList()
        ..sort((a, b) => a.createdAtIso.compareTo(b.createdAtIso));
      if (!mounted) return;
      setState(() {
        _rows = mine;
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

  List<PendingProductPhotoUploadEntry> get _filtered {
    if (_filter == 'ALL') return _rows;
    if (_filter == 'MANUAL') return _rows.where((e) => e.manualReview).toList();
    return _rows.where((e) => !e.manualReview).toList();
  }

  Future<void> _retryNow(PendingProductPhotoUploadEntry entry) async {
    if (_retryingNow) return;
    setState(() => _retryingNow = true);
    try {
      final all = await widget.localPrefs.loadPendingProductPhotoUploads();
      final i = all.indexWhere((e) => e.opId == entry.opId);
      if (i >= 0) {
        final old = all[i];
        all[i] = PendingProductPhotoUploadEntry(
          opId: old.opId,
          storeId: old.storeId,
          productId: old.productId,
          localFilePath: old.localFilePath,
          createdAtIso: old.createdAtIso,
          attemptCount: old.attemptCount,
          lastError: old.lastError,
          manualReview: false,
        );
        await widget.localPrefs.savePendingProductPhotoUploads(all);
      }

      final api = ApiClient();
      final uploadsApi = UploadsApi(api);
      final productsApi = ProductsApi(api);
      try {
        await flushPendingProductPhotoUploads(
          storeId: widget.storeId,
          prefs: widget.localPrefs,
          uploader: (e) async {
            final upload = await uploadsApi.uploadProductImage(
              widget.storeId,
              filePath: e.localFilePath,
            );
            await productsApi.associateProductImage(
              widget.storeId,
              e.productId,
              imageUrl: upload.url,
            );
          },
        );
      } finally {
        api.close();
      }

      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reintento ejecutado. Revisá el estado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo reintentar: $e')),
      );
    } finally {
      if (mounted) setState(() => _retryingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cola de fotos'),
        backgroundColor: PosSaleUi.surface,
        foregroundColor: PosSaleUi.text,
      ),
      backgroundColor: PosSaleUi.bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: PosSaleUi.text),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Todas'),
                            selected: _filter == 'ALL',
                            onSelected: (_) => setState(() => _filter = 'ALL'),
                          ),
                          ChoiceChip(
                            label: const Text('Retryable'),
                            selected: _filter == 'RETRY',
                            onSelected: (_) => setState(() => _filter = 'RETRY'),
                          ),
                          ChoiceChip(
                            label: const Text('Revisión manual'),
                            selected: _filter == 'MANUAL',
                            onSelected: (_) => setState(() => _filter = 'MANUAL'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_filtered.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 26),
                          child: Text(
                            'No hay fotos pendientes para este filtro.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: PosSaleUi.textMuted),
                          ),
                        )
                      else
                        ..._filtered.map((e) {
                          final created =
                              DateTime.tryParse(e.createdAtIso)?.toLocal().toString();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Container(
                              decoration: BoxDecoration(
                                color: PosSaleUi.surface2,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          e.manualReview
                                              ? 'REVISIÓN MANUAL'
                                              : 'RETRYABLE',
                                          style: TextStyle(
                                            color: e.manualReview
                                                ? Colors.orangeAccent
                                                : PosSaleUi.text,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: 'Copiar opId',
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(text: e.opId),
                                          );
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('opId copiado'),
                                            ),
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.copy,
                                          size: 18,
                                          color: PosSaleUi.textMuted,
                                        ),
                                      ),
                                      if (e.manualReview)
                                        TextButton(
                                          onPressed: _retryingNow
                                              ? null
                                              : () => _retryNow(e),
                                          child: const Text('Reintentar ahora'),
                                        ),
                                    ],
                                  ),
                                  Text(
                                    'productId: ${e.productId}',
                                    style: const TextStyle(
                                      color: PosSaleUi.textMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'archivo: ${e.localFilePath}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: PosSaleUi.textFaint,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'intentos: ${e.attemptCount} · creada: ${created ?? e.createdAtIso}',
                                    style: const TextStyle(
                                      color: PosSaleUi.textFaint,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if ((e.lastError ?? '').trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      e.lastError!,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.orangeAccent,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
    );
  }
}

