import 'api_client.dart';

class ProductImageUploadResult {
  const ProductImageUploadResult({
    required this.fileId,
    required this.url,
    required this.mimeType,
    required this.bytes,
  });

  final String fileId;
  final String url;
  final String mimeType;
  final int bytes;

  static ProductImageUploadResult fromJson(Map<String, dynamic> json) {
    return ProductImageUploadResult(
      fileId: json['fileId']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
      bytes: (json['bytes'] is num) ? (json['bytes'] as num).toInt() : 0,
    );
  }
}

class UploadsApi {
  UploadsApi(this._client);

  final ApiClient _client;

  Future<ProductImageUploadResult> uploadProductImage(
    String storeId, {
    required String filePath,
  }) async {
    final json = await _client.postMultipartFile(
      '/uploads/products-image',
      storeId,
      fileFieldName: 'file',
      filePath: filePath,
    );
    return ProductImageUploadResult.fromJson(json);
  }
}

