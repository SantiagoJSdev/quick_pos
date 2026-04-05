/// Operaciones mínimas sobre montos como **string** para no serializar `double` en JSON.
/// Cálculo interno con `double`; resultado formateado para envío al API.
class MoneyStringMath {
  MoneyStringMath._();

  static double _parse(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    return double.parse(t);
  }

  /// `a * b` redondeado a [fractionDigits] (por defecto 2).
  static String multiply(String a, String b, {int fractionDigits = 2}) {
    final v = _parse(a) * _parse(b);
    if (v.isNaN || v.isInfinite) return _zeros(fractionDigits);
    return v.toStringAsFixed(fractionDigits);
  }

  /// `a / b` redondeado a [fractionDigits]; `b == 0` devuelve ceros.
  static String divide(String a, String b, {int fractionDigits = 6}) {
    final denom = _parse(b);
    if (denom == 0) return _zeros(fractionDigits);
    final v = _parse(a) / denom;
    if (v.isNaN || v.isInfinite) return _zeros(fractionDigits);
    return v.toStringAsFixed(fractionDigits);
  }

  static String sum(Iterable<String> values, {int fractionDigits = 2}) {
    var t = 0.0;
    for (final s in values) {
      t += _parse(s);
    }
    if (t.isNaN || t.isInfinite) return _zeros(fractionDigits);
    return t.toStringAsFixed(fractionDigits);
  }

  static String _zeros(int fractionDigits) {
    if (fractionDigits <= 0) return '0';
    return '0.${'0' * fractionDigits}';
  }
}
