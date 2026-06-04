import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';
import '../../domain/dashboard_timeseries.dart';
import '../dashboard_money_format.dart';

class SalesLineChart extends StatelessWidget {
  const SalesLineChart({
    super.key,
    required this.points,
    this.currencyCode,
  });

  final List<TimeSeriesPoint> points;
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        color: PosSaleUi.surface2,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Sin ventas en el período',
              style: TextStyle(color: PosSaleUi.textMuted),
            ),
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      color: PosSaleUi.surface2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ventas netas por día',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: PosSaleUi.text,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: CustomPaint(
                painter: _NetSalesChartPainter(
                  values: points
                      .map((p) => DashboardMoneyFormat.chartValue(p.netSales))
                      .toList(),
                  labels: points.map((p) => _shortBucket(p.bucket)).toList(),
                  lineColor: PosSaleUi.primary,
                ),
                child: Container(),
              ),
            ),
            if (currencyCode != null && currencyCode!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Montos en $currencyCode (moneda funcional)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.textFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _shortBucket(String bucket) {
    if (bucket.length >= 10) return bucket.substring(5);
    return bucket;
  }
}

class _NetSalesChartPainter extends CustomPainter {
  _NetSalesChartPainter({
    required this.values,
    required this.labels,
    required this.lineColor,
  });

  final List<double> values;
  final List<String> labels;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final scaleMax = maxV <= 0 ? 1.0 : maxV;
    final padL = 8.0;
    final padR = 8.0;
    final padT = 8.0;
    final padB = 28.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;
    final n = values.length;

    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = padL + (n == 1 ? w / 2 : w * i / (n - 1));
      final y = padT + h * (1 - values[i] / scaleMax);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);

    final fillPath = Path.from(path)
      ..lineTo(padL + (n == 1 ? w / 2 : w), padT + h)
      ..lineTo(padL, padT + h)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..color = lineColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );

    for (var i = 0; i < n; i++) {
      final x = padL + (n == 1 ? w / 2 : w * i / (n - 1));
      final y = padT + h * (1 - values[i] / scaleMax);
      canvas.drawCircle(Offset(x, y), 4, Paint()..color = lineColor);
    }

    final labelStyle = TextStyle(
      color: PosSaleUi.textFaint,
      fontSize: 10,
    );
    for (var i = 0; i < n && i < labels.length; i++) {
      if (n > 7 && i % 2 != 0 && i != n - 1) continue;
      final x = padL + (n == 1 ? w / 2 : w * i / (n - 1));
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, size.height - padB + 4),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NetSalesChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}
