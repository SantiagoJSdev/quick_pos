import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'pos_sale_ui_tokens.dart';

/// Escaneo de código de barras / QR → texto. **P1** (Venta) y **B7** (Inventario).
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  /// Cámara solo en Android/iOS (no web ni desktop).
  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScanOverlayPainter extends CustomPainter {
  _BarcodeScanOverlayPainter({required this.hole});

  final RRect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cut = Path()..addRRect(hole);
    final overlay = Path.combine(PathOperation.difference, bg, cut);
    canvas.drawPath(overlay, Paint()..color = const Color(0x99000000));
  }

  @override
  bool shouldRepaint(covariant _BarcodeScanOverlayPainter oldDelegate) =>
      oldDelegate.hole != hole;
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with SingleTickerProviderStateMixin {
  final MobileScannerController _controller = MobileScannerController();
  late final AnimationController _frameCtrl;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _frameCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _frameCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue ?? b.displayValue;
      if (v != null && v.trim().isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop<String>(v.trim());
        return;
      }
    }
  }

  Widget _cornerBorder({required bool top, required bool left}) {
    const side = BorderSide(color: PosSaleUi.primary, width: 3);
    final border = Border(
      top: top ? side : BorderSide.none,
      bottom: !top ? side : BorderSide.none,
      left: left ? side : BorderSide.none,
      right: !left ? side : BorderSide.none,
    );
    return DecoratedBox(decoration: BoxDecoration(border: border));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Escanear código'),
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop<String>(),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          const box = 220.0;
          final left = (w - box) / 2;
          final top = (h - box) / 2 - 28;
          final hole = RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, box, box),
            const Radius.circular(16),
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
              IgnorePointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _BarcodeScanOverlayPainter(hole: hole),
                      size: Size(w, h),
                    ),
                    Positioned(
                      left: left,
                      top: top,
                      width: box,
                      height: box,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            width: 26,
                            height: 26,
                            child: _cornerBorder(top: true, left: true),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            width: 26,
                            height: 26,
                            child: _cornerBorder(top: true, left: false),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            width: 26,
                            height: 26,
                            child: _cornerBorder(top: false, left: true),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            width: 26,
                            height: 26,
                            child: _cornerBorder(top: false, left: false),
                          ),
                          AnimatedBuilder(
                            animation: _frameCtrl,
                            builder: (context, child) {
                              final t = _frameCtrl.value;
                              final lineTop = box * (0.15 + t * 0.65);
                              return Positioned(
                                top: lineTop,
                                left: 12,
                                right: 12,
                                child: Container(
                                  height: 2,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        PosSaleUi.primary
                                            .withValues(alpha: 0.9),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 32,
                child: Text(
                  'Apuntá al código de barras o QR del producto.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black),
                        ],
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
