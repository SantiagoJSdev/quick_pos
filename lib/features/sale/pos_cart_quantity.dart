/// Cantidades del carrito POS como string decimal (API y `MoneyStringMath`).
class PosCartQuantity {
  PosCartQuantity._();

  static double parse(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? 0;
  }

  static String stringify(double v) {
    if (v.isNaN || v.isInfinite || v <= 0) return '1';
    final s = v.toStringAsFixed(6);
    var out = s.replaceFirst(RegExp(r'0+$'), '');
    out = out.replaceFirst(RegExp(r'\.$'), '');
    return out.isEmpty ? '1' : out;
  }

  static String normalize(String raw) {
    final v = parse(raw);
    if (v <= 0) return '1';
    return stringify(v);
  }

  /// Cantidad en kg desde el sheet por peso: no recorta decimales (evita
  /// `0.363636` → `0.3636` y totales Bs distintos al acordado).
  static String normalizeWeightKg(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return '1';
    final v = parse(t);
    if (v <= 0) return '1';
    return t;
  }

  static String add(String a, String b) => stringify(parse(a) + parse(b));
}
