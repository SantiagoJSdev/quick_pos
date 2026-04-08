class PendingCatalogMutationEntry {
  const PendingCatalogMutationEntry({
    required this.opId,
    required this.storeId,
    required this.type,
    required this.createdAtIso,
    this.productId,
    this.localTempId,
    this.idempotencyKey,
    this.body,
  });

  final String opId;
  final String storeId;
  final String type;
  final String createdAtIso;
  final String? productId;
  final String? localTempId;
  final String? idempotencyKey;
  final Map<String, dynamic>? body;

  static const typeCreate = 'CREATE_PRODUCT';
  static const typeUpdate = 'UPDATE_PRODUCT';
  static const typeDeactivate = 'DEACTIVATE_PRODUCT';
  static const typeCreateWithStock = 'CREATE_PRODUCT_WITH_STOCK';

  Map<String, dynamic> toJson() {
    return {
      'opId': opId,
      'storeId': storeId,
      'type': type,
      'createdAtIso': createdAtIso,
      if (productId != null) 'productId': productId,
      if (localTempId != null) 'localTempId': localTempId,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
      if (body != null) 'body': body,
    };
  }

  static PendingCatalogMutationEntry? tryFromJson(Map<String, dynamic> json) {
    final opId = json['opId']?.toString().trim() ?? '';
    final storeId = json['storeId']?.toString().trim() ?? '';
    final type = json['type']?.toString().trim() ?? '';
    final createdAtIso = json['createdAtIso']?.toString().trim() ?? '';
    if (opId.isEmpty || storeId.isEmpty || type.isEmpty || createdAtIso.isEmpty) {
      return null;
    }
    final rawBody = json['body'];
    Map<String, dynamic>? body;
    if (rawBody is Map) body = Map<String, dynamic>.from(rawBody);
    return PendingCatalogMutationEntry(
      opId: opId,
      storeId: storeId,
      type: type,
      createdAtIso: createdAtIso,
      productId: json['productId']?.toString(),
      localTempId: json['localTempId']?.toString(),
      idempotencyKey: json['idempotencyKey']?.toString(),
      body: body,
    );
  }
}
