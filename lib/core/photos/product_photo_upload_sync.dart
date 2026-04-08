import 'dart:io';

import '../api/api_error.dart';
import '../storage/local_prefs.dart';
import 'pending_product_photo_upload_entry.dart';

typedef ProductPhotoUploader = Future<void> Function(
  PendingProductPhotoUploadEntry entry,
);

class ProductPhotoUploadFlushResult {
  const ProductPhotoUploadFlushResult({
    required this.total,
    required this.uploaded,
    required this.updatedAsFailed,
    required this.removedMissingFile,
    required this.markedManualReview,
  });

  final int total;
  final int uploaded;
  final int updatedAsFailed;
  final int removedMissingFile;
  final int markedManualReview;
}

/// Worker de cola de fotos:
/// - Si [uploader] es null, hace housekeeping (elimina archivos inexistentes).
/// - Si [uploader] existe, intenta subir en orden y aplica retry metadata.
Future<ProductPhotoUploadFlushResult> flushPendingProductPhotoUploads({
  required String storeId,
  required LocalPrefs prefs,
  ProductPhotoUploader? uploader,
}) async {
  final all = await prefs.loadPendingProductPhotoUploads();
  if (all.isEmpty) {
    return const ProductPhotoUploadFlushResult(
      total: 0,
      uploaded: 0,
      updatedAsFailed: 0,
      removedMissingFile: 0,
      markedManualReview: 0,
    );
  }

  final mine = all.where((e) => e.storeId == storeId).toList()
    ..sort((a, b) => a.createdAtIso.compareTo(b.createdAtIso));
  if (mine.isEmpty) {
    return const ProductPhotoUploadFlushResult(
      total: 0,
      uploaded: 0,
      updatedAsFailed: 0,
      removedMissingFile: 0,
      markedManualReview: 0,
    );
  }

  var uploaded = 0;
  var failed = 0;
  var removedMissing = 0;
  var markedManual = 0;
  final next = List<PendingProductPhotoUploadEntry>.from(all);

  for (final e in mine) {
    if (e.manualReview) {
      continue;
    }
    final f = File(e.localFilePath);
    if (!f.existsSync()) {
      next.removeWhere((x) => x.opId == e.opId);
      removedMissing++;
      continue;
    }

    if (uploader == null) {
      continue;
    }

    try {
      await uploader(e);
      next.removeWhere((x) => x.opId == e.opId);
      uploaded++;
    } on ApiError catch (err) {
      final i = next.indexWhere((x) => x.opId == e.opId);
      if (i >= 0) {
        final manual = err.isManualReviewSyncFailure;
        next[i] = PendingProductPhotoUploadEntry(
          opId: e.opId,
          storeId: e.storeId,
          productId: e.productId,
          localFilePath: e.localFilePath,
          createdAtIso: e.createdAtIso,
          attemptCount: e.attemptCount + 1,
          lastError: err.userMessageForSupport,
          manualReview: manual,
        );
        if (manual) markedManual++;
      }
      failed++;
      break;
    } catch (err) {
      final i = next.indexWhere((x) => x.opId == e.opId);
      if (i >= 0) {
        next[i] = PendingProductPhotoUploadEntry(
          opId: e.opId,
          storeId: e.storeId,
          productId: e.productId,
          localFilePath: e.localFilePath,
          createdAtIso: e.createdAtIso,
          attemptCount: e.attemptCount + 1,
          lastError: err.toString(),
          manualReview: e.manualReview,
        );
      }
      failed++;
      break;
    }
  }

  await prefs.savePendingProductPhotoUploads(next);
  return ProductPhotoUploadFlushResult(
    total: mine.length,
    uploaded: uploaded,
    updatedAsFailed: failed,
    removedMissingFile: removedMissing,
    markedManualReview: markedManual,
  );
}

