/// Respuesta de `GET /api/v1/kpis/snapshot` — `docs/KPI_SNAPSHOT_FRONTEND.md`.
class KpiSnapshot {
  const KpiSnapshot({
    required this.currencyCode,
    this.from,
    this.to,
    this.timezone,
    this.preset,
    this.grossProfit,
    this.realProfit,
    this.payables,
    this.stockAlerts,
    this.loadedAt,
  });

  final String currencyCode;
  final String? from;
  final String? to;
  final String? timezone;
  final String? preset;
  final KpiGrossProfit? grossProfit;
  final KpiRealProfit? realProfit;
  final KpiPayables? payables;
  final KpiStockAlerts? stockAlerts;
  final DateTime? loadedAt;

  String get periodLabel {
    final a = from?.trim() ?? '';
    final b = to?.trim() ?? '';
    if (a.isEmpty && b.isEmpty) return currencyCode;
    if (a == b || b.isEmpty) return '$a · $currencyCode';
    return '$a → $b · $currencyCode';
  }

  static KpiSnapshot fromJson(Map<String, dynamic> json) {
    final meta = json['meta'] is Map
        ? Map<String, dynamic>.from(json['meta'] as Map)
        : json;
    return KpiSnapshot(
      currencyCode: (meta['currencyCode'] ?? json['currencyCode'] ?? '')
          .toString()
          .trim(),
      from: (meta['from'] ?? json['from'])?.toString(),
      to: (meta['to'] ?? json['to'])?.toString(),
      timezone: (meta['timezone'] ?? json['timezone'])?.toString(),
      preset: (meta['preset'] ?? json['preset'])?.toString(),
      grossProfit: KpiGrossProfit.tryFromJson(_map(json['grossProfit'])),
      realProfit: KpiRealProfit.tryFromJson(_map(json['realProfit'])),
      payables: KpiPayables.tryFromJson(_map(json['payables'])),
      stockAlerts: KpiStockAlerts.tryFromJson(_map(json['stockAlerts'])),
      loadedAt: DateTime.now(),
    );
  }

  static Map<String, dynamic>? _map(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }
}

class KpiGrossDayPoint {
  const KpiGrossDayPoint({
    required this.date,
    this.netSales,
    this.cogs,
    this.grossProfit,
  });

  final String date;
  final String? netSales;
  final String? cogs;
  final String? grossProfit;

  static KpiGrossDayPoint? tryFromJson(Map<String, dynamic> json) {
    final date = json['date']?.toString().trim() ?? '';
    if (date.isEmpty) return null;
    return KpiGrossDayPoint(
      date: date,
      netSales: json['netSales']?.toString(),
      cogs: json['cogs']?.toString(),
      grossProfit: json['grossProfit']?.toString(),
    );
  }
}

class KpiGrossProfit {
  const KpiGrossProfit({
    this.netSales,
    this.cogs,
    this.grossProfit,
    this.marginPercent,
    this.byDay = const [],
  });

  final String? netSales;
  final String? cogs;
  final String? grossProfit;
  final String? marginPercent;
  final List<KpiGrossDayPoint> byDay;

  static KpiGrossProfit? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final days = <KpiGrossDayPoint>[];
    final raw = json['byDay'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final p = KpiGrossDayPoint.tryFromJson(Map<String, dynamic>.from(e));
          if (p != null) days.add(p);
        }
      }
    }
    return KpiGrossProfit(
      netSales: json['netSales']?.toString(),
      cogs: json['cogs']?.toString(),
      grossProfit: json['grossProfit']?.toString(),
      marginPercent: json['marginPercent']?.toString(),
      byDay: days,
    );
  }
}

class KpiDeductionBags {
  const KpiDeductionBags({
    this.tickets,
    this.bagsEstimated,
    this.amount,
  });

  final String? tickets;
  final String? bagsEstimated;
  final String? amount;

  static KpiDeductionBags? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return KpiDeductionBags(
      tickets: json['tickets']?.toString(),
      bagsEstimated: json['bagsEstimated']?.toString(),
      amount: json['amount']?.toString(),
    );
  }
}

class KpiDeductionCharcuterie {
  const KpiDeductionCharcuterie({
    this.units,
    this.unitCost,
    this.amount,
  });

  final String? units;
  final String? unitCost;
  final String? amount;

  static KpiDeductionCharcuterie? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return KpiDeductionCharcuterie(
      units: json['units']?.toString(),
      unitCost: json['unitCost']?.toString(),
      amount: json['amount']?.toString(),
    );
  }
}

class KpiPayrollLine {
  const KpiPayrollLine({
    this.name,
    this.amount,
  });

  final String? name;
  final String? amount;

  static KpiPayrollLine? tryFromJson(Map<String, dynamic> json) {
    return KpiPayrollLine(
      name: json['name']?.toString() ?? json['employeeName']?.toString(),
      amount: json['amount']?.toString(),
    );
  }
}

class KpiDeductionPayroll {
  const KpiDeductionPayroll({
    this.amount,
    this.employees = const [],
  });

  final String? amount;
  final List<KpiPayrollLine> employees;

  static KpiDeductionPayroll? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final list = <KpiPayrollLine>[];
    final raw = json['employees'] ?? json['items'] ?? json['lines'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final line = KpiPayrollLine.tryFromJson(Map<String, dynamic>.from(e));
          if (line != null) list.add(line);
        }
      }
    }
    return KpiDeductionPayroll(
      amount: json['amount']?.toString() ?? json['total']?.toString(),
      employees: list,
    );
  }
}

class KpiDeductionFixed {
  const KpiDeductionFixed({
    this.electricity,
    this.rent,
    this.transport,
    this.amount,
  });

  final String? electricity;
  final String? rent;
  final String? transport;
  final String? amount;

  static KpiDeductionFixed? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return KpiDeductionFixed(
      electricity: json['electricity']?.toString() ?? json['luz']?.toString(),
      rent: json['rent']?.toString() ?? json['alquiler']?.toString(),
      transport:
          json['transport']?.toString() ?? json['transporte']?.toString(),
      amount: json['amount']?.toString() ?? json['total']?.toString(),
    );
  }
}

class KpiDeductions {
  const KpiDeductions({
    this.total,
    this.bags,
    this.charcuterieWrap,
    this.payroll,
    this.fixed,
  });

  final String? total;
  final KpiDeductionBags? bags;
  final KpiDeductionCharcuterie? charcuterieWrap;
  final KpiDeductionPayroll? payroll;
  final KpiDeductionFixed? fixed;

  static KpiDeductions? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return KpiDeductions(
      total: json['total']?.toString(),
      bags: KpiDeductionBags.tryFromJson(
        json['bags'] is Map
            ? Map<String, dynamic>.from(json['bags'] as Map)
            : null,
      ),
      charcuterieWrap: KpiDeductionCharcuterie.tryFromJson(
        json['charcuterieWrap'] is Map
            ? Map<String, dynamic>.from(json['charcuterieWrap'] as Map)
            : null,
      ),
      payroll: KpiDeductionPayroll.tryFromJson(
        json['payroll'] is Map
            ? Map<String, dynamic>.from(json['payroll'] as Map)
            : null,
      ),
      fixed: KpiDeductionFixed.tryFromJson(
        json['fixed'] is Map
            ? Map<String, dynamic>.from(json['fixed'] as Map)
            : null,
      ),
    );
  }
}

class KpiRealProfit {
  const KpiRealProfit({
    this.realProfit,
    this.realMarginPercent,
    this.phase,
    this.calendarDays,
    this.deductions,
  });

  final String? realProfit;
  final String? realMarginPercent;
  final String? phase;
  final int? calendarDays;
  final KpiDeductions? deductions;

  static KpiRealProfit? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    int? days;
    final d = json['calendarDays'];
    if (d is int) {
      days = d;
    } else if (d != null) {
      days = int.tryParse(d.toString());
    }
    return KpiRealProfit(
      realProfit: json['realProfit']?.toString(),
      realMarginPercent: json['realMarginPercent']?.toString(),
      phase: json['phase']?.toString(),
      calendarDays: days,
      deductions: KpiDeductions.tryFromJson(
        json['deductions'] is Map
            ? Map<String, dynamic>.from(json['deductions'] as Map)
            : null,
      ),
    );
  }
}

class KpiAgingBucket {
  const KpiAgingBucket({
    this.amountDueFunctional,
    this.invoiceCount,
  });

  final String? amountDueFunctional;
  final int? invoiceCount;

  static KpiAgingBucket? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    int? count;
    final c = json['invoiceCount'] ?? json['count'];
    if (c is int) {
      count = c;
    } else if (c != null) {
      count = int.tryParse(c.toString());
    }
    return KpiAgingBucket(
      amountDueFunctional: json['amountDueFunctional']?.toString() ??
          json['amount']?.toString(),
      invoiceCount: count,
    );
  }
}

class KpiPayablesAging {
  const KpiPayablesAging({
    this.overdue,
    this.dueToday,
    this.dueNext7Days,
    this.laterOrNoDueDate,
  });

  final KpiAgingBucket? overdue;
  final KpiAgingBucket? dueToday;
  final KpiAgingBucket? dueNext7Days;
  final KpiAgingBucket? laterOrNoDueDate;

  static KpiPayablesAging? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    Map<String, dynamic>? m(Object? v) =>
        v is Map ? Map<String, dynamic>.from(v) : null;
    return KpiPayablesAging(
      overdue: KpiAgingBucket.tryFromJson(m(json['overdue'])),
      dueToday: KpiAgingBucket.tryFromJson(m(json['dueToday'])),
      dueNext7Days: KpiAgingBucket.tryFromJson(m(json['dueNext7Days'])),
      laterOrNoDueDate: KpiAgingBucket.tryFromJson(m(json['laterOrNoDueDate'])),
    );
  }
}

class KpiPayableByDay {
  const KpiPayableByDay({
    this.date,
    this.amountDueFunctional,
    this.invoiceCount,
  });

  final String? date;
  final String? amountDueFunctional;
  final int? invoiceCount;

  static KpiPayableByDay? tryFromJson(Map<String, dynamic> json) {
    int? count;
    final c = json['invoiceCount'] ?? json['count'];
    if (c is int) {
      count = c;
    } else if (c != null) {
      count = int.tryParse(c.toString());
    }
    return KpiPayableByDay(
      date: json['date']?.toString(),
      amountDueFunctional: json['amountDueFunctional']?.toString(),
      invoiceCount: count,
    );
  }
}

class KpiPayables {
  const KpiPayables({
    this.totalDueFunctional,
    this.openInvoiceCount,
    this.asOf,
    this.aging,
    this.byDay = const [],
  });

  final String? totalDueFunctional;
  final int? openInvoiceCount;
  final String? asOf;
  final KpiPayablesAging? aging;
  final List<KpiPayableByDay> byDay;

  static KpiPayables? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    int? count;
    final c = json['openInvoiceCount'] ?? json['openInvoices'];
    if (c is int) {
      count = c;
    } else if (c != null) {
      count = int.tryParse(c.toString());
    }
    final days = <KpiPayableByDay>[];
    final raw = json['byDay'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final p = KpiPayableByDay.tryFromJson(Map<String, dynamic>.from(e));
          if (p != null) days.add(p);
        }
      }
    }
    return KpiPayables(
      totalDueFunctional: json['totalDueFunctional']?.toString(),
      openInvoiceCount: count,
      asOf: json['asOf']?.toString(),
      aging: KpiPayablesAging.tryFromJson(
        json['aging'] is Map
            ? Map<String, dynamic>.from(json['aging'] as Map)
            : null,
      ),
      byDay: days,
    );
  }
}

class KpiStockAlertItem {
  const KpiStockAlertItem({
    this.productId,
    this.sku,
    this.name,
    this.available,
    this.threshold,
  });

  final String? productId;
  final String? sku;
  final String? name;
  final String? available;
  final String? threshold;

  static KpiStockAlertItem? tryFromJson(Map<String, dynamic> json) {
    return KpiStockAlertItem(
      productId: json['productId']?.toString() ?? json['id']?.toString(),
      sku: json['sku']?.toString(),
      name: json['name']?.toString() ?? json['productName']?.toString(),
      available: json['available']?.toString() ?? json['quantity']?.toString(),
      threshold: json['threshold']?.toString() ?? json['minStock']?.toString(),
    );
  }
}

class KpiStockAlerts {
  const KpiStockAlerts({
    this.negativeCount,
    this.lowCount,
    this.negatives = const [],
    this.low = const [],
    this.defaultLowUnits,
    this.defaultLowKg,
  });

  final int? negativeCount;
  final int? lowCount;
  final List<KpiStockAlertItem> negatives;
  final List<KpiStockAlertItem> low;
  final String? defaultLowUnits;
  final String? defaultLowKg;

  static KpiStockAlerts? tryFromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    int? i(Object? v) {
      if (v is int) return v;
      if (v == null) return null;
      return int.tryParse(v.toString());
    }

    List<KpiStockAlertItem> parseList(Object? raw) {
      final out = <KpiStockAlertItem>[];
      if (raw is List) {
        for (final e in raw) {
          if (e is Map) {
            final item =
                KpiStockAlertItem.tryFromJson(Map<String, dynamic>.from(e));
            if (item != null) out.add(item);
          }
        }
      }
      return out;
    }

    final defaults = json['defaults'] is Map
        ? Map<String, dynamic>.from(json['defaults'] as Map)
        : null;

    return KpiStockAlerts(
      negativeCount: i(json['negativeCount']),
      lowCount: i(json['lowCount']),
      negatives: parseList(json['negatives']),
      low: parseList(json['low']),
      defaultLowUnits: defaults?['lowUnits']?.toString(),
      defaultLowKg: defaults?['lowKg']?.toString(),
    );
  }
}
