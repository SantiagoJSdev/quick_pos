/// Formato de montos API (`String`) para UI — sin recalcular KPIs del backend.
class DashboardMoneyFormat {
  DashboardMoneyFormat._();

  static String displayAmount(String amount, {String? currencyCode}) {
    final v = _parse(amount);
    final parts = v.toStringAsFixed(2).split('.');
    final intPart = _groupThousands(parts[0]);
    final dec = parts.length > 1 ? parts[1] : '00';
    final core = '$intPart,$dec';
    if (currencyCode != null && currencyCode.isNotEmpty) {
      return '$core $currencyCode';
    }
    return core;
  }

  static String? displayReturnRate(String? returnRate) {
    if (returnRate == null || returnRate.trim().isEmpty) return null;
    final v = _parse(returnRate);
    if (v.isNaN) return null;
    return '${(v * 100).toStringAsFixed(1)} %';
  }

  /// Solo para escala del gráfico (no para KPIs oficiales).
  static double chartValue(String amount) => _parse(amount);

  static String _groupThousands(String digits) {
    if (digits.length <= 3) return digits;
    final neg = digits.startsWith('-');
    final d = neg ? digits.substring(1) : digits;
    final buf = StringBuffer();
    var i = 0;
    for (final c in d.split('').reversed) {
      if (i > 0 && i % 3 == 0) buf.write('.');
      buf.write(c);
      i++;
    }
    final grouped = buf.toString().split('').reversed.join();
    return neg ? '-$grouped' : grouped;
  }

  static double _parse(String s) {
    final t = s.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    return double.tryParse(t) ?? 0;
  }
}
