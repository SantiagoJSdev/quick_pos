/// Proveedor guardado solo en el dispositivo (C1/C2) hasta exista API.
class LocalSupplier {
  const LocalSupplier({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static LocalSupplier? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    return LocalSupplier(id: id, name: name);
  }
}
