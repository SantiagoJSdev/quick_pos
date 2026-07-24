import 'package:flutter/material.dart';

import '../../../../core/api/api_error.dart';
import '../../../sale/pos_sale_ui_tokens.dart';
import '../../data/dashboard_repository.dart';
import '../controllers/dashboard_controller.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/kpi_row.dart';
import '../widgets/last_updated_banner.dart';
import '../widgets/payments_breakdown_list.dart';
import '../widgets/sales_line_chart.dart';

class DashboardHomeScreen extends StatefulWidget {
  const DashboardHomeScreen({
    super.key,
    required this.storeId,
    required this.repository,
    this.shellOnline = true,
  });

  final String storeId;
  final DashboardRepository repository;
  final bool shellOnline;

  @override
  State<DashboardHomeScreen> createState() => _DashboardHomeScreenState();
}

class _DashboardHomeScreenState extends State<DashboardHomeScreen> {
  late final DashboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(
      repository: widget.repository,
      storeId: widget.storeId,
    )..load();
    _controller.addListener(_onController);
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onController);
    _controller.dispose();
    super.dispose();
  }

  Future<({String from, String to})?> _pickCustomRange() async {
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 6)),
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Desde',
    );
    if (from == null || !mounted) return null;
    final to = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: from,
      lastDate: now,
      helpText: 'Hasta',
    );
    if (to == null) return null;
    return (
      from: _formatDate(from),
      to: _formatDate(to),
    );
  }

  static String _formatDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosSaleUi.bg,
      appBar: AppBar(
        title: const Text('Dashboard operativo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: widget.shellOnline ? () => _controller.load() : null,
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: Column(
        children: [
          if (!widget.shellOnline)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(10),
              child: const Text(
                'Sin conexión — el dashboard requiere red en v1.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          if (_controller.status == DashboardLoadStatus.success &&
              _controller.data != null)
            LastUpdatedBanner(updatedAt: _controller.data!.loadedAt),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!widget.shellOnline) {
      return const Center(
        child: Text(
          'Conectate para ver reportes del servidor.',
          style: TextStyle(color: PosSaleUi.textMuted),
        ),
      );
    }

    switch (_controller.status) {
      case DashboardLoadStatus.idle:
      case DashboardLoadStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case DashboardLoadStatus.error:
        return _errorBody();
      case DashboardLoadStatus.success:
        final data = _controller.data;
        if (data == null) {
          return const Center(child: Text('Sin datos'));
        }
        return RefreshIndicator(
          onRefresh: () => _controller.load(),
          color: PosSaleUi.primary,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              24 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              DateRangeSelector(
                current: _controller.filters,
                onChanged: _controller.setFilters,
                onCustomRange: _pickCustomRange,
              ),
              const SizedBox(height: 8),
              Text(
                data.periodLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: PosSaleUi.textMuted,
                ),
              ),
              if (data.totalsCorrectedForCaracas) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8A34A).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Totales ajustados al día en Venezuela (UTC−4). '
                    'En el servidor la tienda está en UTC; pedile al backend '
                    'cambiar timezone a America/Caracas.',
                    style: TextStyle(
                      color: Color(0xFFE8A34A),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              KpiRow(data: data),
              const SizedBox(height: 16),
              SalesLineChart(
                points: data.timeSeries.points,
                currencyCode: data.currencyCode,
              ),
              const SizedBox(height: 16),
              PaymentsBreakdownList(
                items: data.payments.items,
                currencyCode: data.currencyCode,
              ),
            ],
          ),
        );
    }
  }

  Widget _errorBody() {
    final msg = _controller.message ?? 'Error al cargar';
    final is400 = _controller.error?.statusCode == 400;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PosSaleUi.textMuted),
            ),
            if (_controller.error is ApiError &&
                (_controller.error as ApiError).requestId != null) ...[
              const SizedBox(height: 8),
              Text(
                'requestId: ${(_controller.error as ApiError).requestId}',
                style: const TextStyle(
                  fontSize: 11,
                  color: PosSaleUi.textFaint,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _controller.load(),
              child: Text(is400 ? 'Elegir otro rango' : 'Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
