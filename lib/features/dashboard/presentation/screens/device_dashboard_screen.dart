import 'package:flutter/material.dart';

import '../../../sale/pos_sale_ui_tokens.dart';
import '../../data/dashboard_repository.dart';
import '../controllers/device_dashboard_controller.dart';
import '../dashboard_money_format.dart';
import '../widgets/last_updated_banner.dart';
import '../widgets/payments_breakdown_list.dart';
import '../widgets/sales_line_chart.dart';

class DeviceDashboardScreen extends StatefulWidget {
  const DeviceDashboardScreen({
    super.key,
    required this.deviceId,
    required this.deviceToken,
    required this.repository,
    this.onExitKiosk,
  });

  final String deviceId;
  final String deviceToken;
  final DashboardRepository repository;
  final VoidCallback? onExitKiosk;

  @override
  State<DeviceDashboardScreen> createState() => _DeviceDashboardScreenState();
}

class _DeviceDashboardScreenState extends State<DeviceDashboardScreen> {
  late final DeviceDashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DeviceDashboardController(
      repository: widget.repository,
      deviceId: widget.deviceId,
      deviceToken: widget.deviceToken,
    )..startAutoRefresh();
    _controller.addListener(_onUpdate);
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosSaleUi.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            LastUpdatedBanner(
              updatedAt: _controller.lastUpdatedAt,
              offlineCache: _controller.fromCache,
            ),
            Expanded(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text(
            'Dashboard · Hoy',
            style: TextStyle(
              color: PosSaleUi.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (widget.onExitKiosk != null)
            TextButton(
              onPressed: widget.onExitKiosk,
              child: const Text('Salir'),
            ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_controller.status) {
      case DeviceDashboardStatus.idle:
      case DeviceDashboardStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case DeviceDashboardStatus.unauthorized:
        return _statusPanel(
          context,
          title: 'Dispositivo no autorizado',
          message: _controller.message ??
              'Token inválido o dispositivo no registrado.',
          actionLabel: 'Reconfigurar',
          onAction: _openSetup,
        );
      case DeviceDashboardStatus.disabled:
        return _statusPanel(
          context,
          title: 'Dashboard desactivado',
          message: _controller.message ??
              'Un administrador debe activar el modo dashboard.',
          actionLabel: 'Configurar',
          onAction: _openSetup,
        );
      case DeviceDashboardStatus.error:
        return _statusPanel(
          context,
          title: 'Error de conexión',
          message: _controller.message ?? 'No se pudo cargar el dashboard.',
          actionLabel: 'Reintentar',
          onAction: () => _controller.refresh(),
        );
      case DeviceDashboardStatus.success:
        final p = _controller.payload;
        if (p == null) {
          return const Center(child: Text('Sin datos'));
        }
        final s = p.summary;
        final cur = p.currencyCode;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: _KioskKpi(
                    title: 'Ventas netas',
                    value: DashboardMoneyFormat.displayAmount(
                      s.netSales,
                      currencyCode: cur,
                    ),
                    color: PosSaleUi.success,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KioskKpi(
                    title: 'Tickets',
                    value: '${s.tickets}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KioskKpi(
                    title: 'Devoluciones',
                    value: DashboardMoneyFormat.displayAmount(
                      s.returns,
                      currencyCode: cur,
                    ),
                    color: const Color(0xFFE8A34A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SalesLineChart(points: p.series, currencyCode: cur),
            const SizedBox(height: 16),
            PaymentsBreakdownList(
              items: p.payments,
              currencyCode: cur,
            ),
          ],
        );
    }
  }

  Future<void> _openSetup() async {
    // Reconfigurar requiere volver al flujo POS con tienda vinculada.
    if (widget.onExitKiosk != null) {
      widget.onExitKiosk!();
    }
  }

  Widget _statusPanel(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.tv_off_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: PosSaleUi.text,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PosSaleUi.textMuted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _KioskKpi extends StatelessWidget {
  const _KioskKpi({
    required this.title,
    required this.value,
    this.color,
  });

  final String title;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: PosSaleUi.surface2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: PosSaleUi.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: color ?? PosSaleUi.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
