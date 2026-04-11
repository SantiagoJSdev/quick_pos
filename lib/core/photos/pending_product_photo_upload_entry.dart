class PendingProductPhotoUploadEntry {
  const PendingProductPhotoUploadEntry({
    required this.opId,
    required this.storeId,
    required this.productId,
    required this.localFilePath,
    required this.createdAtIso,
    this.attemptCount = 0,
    this.lastError,
    this.manualReview = false,
  });

  final String opId;
  final String storeId;
  final String productId;
  final String localFilePath;
  final String createdAtIso;
  final int attemptCount;
  final String? lastError;
  final bool manualReview;

  Map<String, dynamic> toJson() {
    return {
      'opId': opId,
      'storeId': storeId,
      'productId': productId,
      'localFilePath': localFilePath,
      'createdAtIso': createdAtIso,
      'attemptCount': attemptCount,
      if (lastError != null) 'lastError': lastError,
      'manualReview': manualReview,
    };
  }

  static PendingProductPhotoUploadEntry? tryFromJson(
    Map<String, dynamic> json,
  ) {
    final opId = json['opId']?.toString().trim() ?? '';
    final storeId = json['storeId']?.toString().trim() ?? '';
    final productId = json['productId']?.toString().trim() ?? '';
    final localFilePath = json['localFilePath']?.toString().trim() ?? '';
    final createdAtIso = json['createdAtIso']?.toString().trim() ?? '';
    if (opId.isEmpty ||
        storeId.isEmpty ||
        productId.isEmpty ||
        localFilePath.isEmpty ||
        createdAtIso.isEmpty) {
      return null;
    }
    final rawAttempts = json['attemptCount'];
    final attempts = rawAttempts is num ? rawAttempts.toInt() : 0;
    final manualReview = json['manualReview'] == true;
    return PendingProductPhotoUploadEntry(
      opId: opId,
      storeId: storeId,
      productId: productId,
      localFilePath: localFilePath,
      createdAtIso: createdAtIso,
      attemptCount: attempts < 0 ? 0 : attempts,
      lastError: json['lastError']?.toString(),
      manualReview: manualReview,
    );
  }
}
