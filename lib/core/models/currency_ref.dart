class CurrencyRef {
  const CurrencyRef({required this.code, this.name});

  final String code;
  final String? name;

  static CurrencyRef? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final code = json['code'] as String?;
    if (code == null) return null;
    return CurrencyRef(
      code: code,
      name: json['name'] as String?,
    );
  }
}
