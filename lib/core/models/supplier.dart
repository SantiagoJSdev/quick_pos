/// Proveedor de `GET/POST/PATCH /api/v1/suppliers` (por tienda, `X-Store-Id`).
class Supplier {
  const Supplier({
    required this.id,
    required this.storeId,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.taxId,
    this.notes,
    required this.active,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String storeId;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxId;
  final String? notes;
  final bool active;
  final String? createdAt;
  final String? updatedAt;

  static Supplier fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id']?.toString() ?? '',
      storeId: json['storeId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      taxId: json['taxId'] as String?,
      notes: json['notes'] as String?,
      active: json['active'] as bool? ?? true,
      createdAt: json['createdAt']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }
}

/// Página de `GET /suppliers` con `items` + `nextCursor`.
class SupplierListPage {
  const SupplierListPage({required this.items, this.nextCursor});

  final List<Supplier> items;
  final String? nextCursor;
}
