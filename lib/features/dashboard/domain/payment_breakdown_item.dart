class PaymentBreakdownItem {
  const PaymentBreakdownItem({
    required this.method,
    required this.amount,
  });

  final String method;
  final String amount;

  factory PaymentBreakdownItem.fromJson(Map<String, dynamic> json) {
    return PaymentBreakdownItem(
      method: json['method']?.toString() ?? '',
      amount: json['amount']?.toString() ?? '0',
    );
  }
}

class SalesPaymentsReport {
  const SalesPaymentsReport({
    required this.storeId,
    required this.currencyCode,
    required this.from,
    required this.to,
    required this.items,
    this.timezone,
    this.preset,
  });

  final String storeId;
  final String currencyCode;
  final String from;
  final String to;
  final String? timezone;
  final String? preset;
  final List<PaymentBreakdownItem> items;

  factory SalesPaymentsReport.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = <PaymentBreakdownItem>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map<String, dynamic>) {
          items.add(PaymentBreakdownItem.fromJson(e));
        } else if (e is Map) {
          items.add(
            PaymentBreakdownItem.fromJson(Map<String, dynamic>.from(e)),
          );
        }
      }
    }
    return SalesPaymentsReport(
      storeId: json['storeId']?.toString() ?? '',
      currencyCode: json['currencyCode']?.toString() ?? '',
      from: json['from']?.toString() ?? '',
      to: json['to']?.toString() ?? '',
      timezone: json['timezone']?.toString(),
      preset: json['preset']?.toString(),
      items: items,
    );
  }
}
