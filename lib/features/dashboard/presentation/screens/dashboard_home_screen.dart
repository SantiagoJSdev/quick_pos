import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/api/api_error.dart';
import '../../../sale/pos_sale_ui_tokens.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/kpi_snapshot.dart';
import '../controllers/dashboard_controller.dart';
import '../widgets/date_range_selector.dart';
import '../widgets/kpi_capital_panel.dart';
import '../widgets/kpi_row.dart';
import '../widgets/kpi_snapshot_panel.dart';
import '../../domain/kpi_capital_series.dart';
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
  int _tab = 0;

  String _kpiPreset = 'today';
  KpiSnapshot? _kpiSnapshot;
  bool _kpiLoading = false;
  String? _kpiError;
  ApiError? _kpiApiError;

  String _capitalPreset = 'week';
  KpiCapitalSeries? _capitalSeries;
  bool _capitalLoading = false;
  String? _capitalError;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController(
      repository: widget.repository,
      storeId: widget.storeId,
    );
    _controller.addListener(_onController);
    if (widget.shellOnline) {
      unawaited(_loadKpis());
      unawaited(_controller.load());
    }
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

  Future<void> _loadKpis() async {
    if (!widget.shellOnline) return;
    setState(() {
      _kpiLoading = true;
      _kpiError = null;
      _kpiApiError = null;
    });
    try {
      final snap = await widget.repository.loadKpiSnapshot(
        widget.storeId,
        preset: _kpiPreset,
      );
      if (!mounted) return;
      setState(() {
        _kpiSnapshot = snap;
        _kpiLoading = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _kpiLoading = false;
        _kpiApiError = e;
        _kpiError = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _kpiLoading = false;
        _kpiError = e.toString();
      });
    }
  }

  Future<void> _setKpiPreset(String preset) async {
    if (_kpiPreset == preset) return;
    setState(() => _kpiPreset = preset);
    await _loadKpis();
  }

  Future<void> _loadCapital() async {
    if (!widget.shellOnline) return;
    setState(() {
      _capitalLoading = true;
      _capitalError = null;
    });
    try {
      final series = await widget.repository.loadCapitalSeries(
        widget.storeId,
        preset: _capitalPreset,
      );
      if (!mounted) return;
      setState(() {
        _capitalSeries = series;
        _capitalLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _capitalLoading = false;
        _capitalError = e is ApiError ? e.userMessageForSupport : e.toString();
      });
    }
  }

  Future<void> _setCapitalPreset(String preset) async {
    if (_capitalPreset == preset) return;
    setState(() => _capitalPreset = preset);
    await _loadCapital();
  }

  Future<void> _refreshCurrent() async {
    if (_tab == 0) {
      await _loadKpis();
    } else if (_tab == 1) {
      await _loadCapital();
    } else {
      await _controller.load();
    }
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
    return (from: _formatDate(from), to: _formatDate(to));
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
            onPressed: widget.shellOnline ? _refreshCurrent : null,
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
                'Sin conexión — el dashboard requiere red.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment<int>(
                  value: 0,
                  label: Text('Hoy'),
                  icon: Icon(Icons.insights_outlined),
                ),
                ButtonSegment<int>(
                  value: 1,
                  label: Text('Capital'),
                  icon: Icon(Icons.account_balance_outlined),
                ),
                ButtonSegment<int>(
                  value: 2,
                  label: Text('Ventas'),
                  icon: Icon(Icons.point_of_sale_outlined),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) {
                setState(() => _tab = s.first);
                if (_tab == 0 && _kpiSnapshot == null && !_kpiLoading) {
                  unawaited(_loadKpis());
                }
                if (_tab == 1 && _capitalSeries == null && !_capitalLoading) {
                  unawaited(_loadCapital());
                }
                if (_tab == 2 &&
                    _controller.status == DashboardLoadStatus.idle) {
                  unawaited(_controller.load());
                }
              },
            ),
          ),
          if (_tab == 0 &&
              _kpiSnapshot?.loadedAt != null &&
              !_kpiLoading)
            LastUpdatedBanner(updatedAt: _kpiSnapshot!.loadedAt!),
          if (_tab == 2 &&
              _controller.status == DashboardLoadStatus.success &&
              _controller.data != null)
            LastUpdatedBanner(updatedAt: _controller.data!.loadedAt),
          Expanded(
            child: !widget.shellOnline
                ? const Center(
                    child: Text(
                      'Conectate para ver el tablero.',
                      style: TextStyle(color: PosSaleUi.textMuted),
                    ),
                  )
                : switch (_tab) {
                    0 => _buildKpiBody(),
                    1 => _buildCapitalBody(),
                    _ => _buildSalesBody(),
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiBody() {
    if (_kpiLoading && _kpiSnapshot == null) {
      return _kpiSkeleton();
    }
    if (_kpiError != null && _kpiSnapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _kpiError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PosSaleUi.textMuted),
              ),
              if (_kpiApiError?.requestId != null) ...[
                const SizedBox(height: 8),
                Text(
                  'requestId: ${_kpiApiError!.requestId}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: PosSaleUi.textFaint,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loadKpis,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_kpiSnapshot == null) {
      return const Center(child: Text('Sin datos KPI'));
    }
    return Stack(
      children: [
        KpiSnapshotPanel(
          snapshot: _kpiSnapshot!,
          preset: _kpiPreset,
          onPresetChanged: _setKpiPreset,
          onRefresh: _loadKpis,
        ),
        if (_kpiLoading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _buildCapitalBody() {
    if (_capitalLoading && _capitalSeries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_capitalError != null && _capitalSeries == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _capitalError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PosSaleUi.textMuted),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loadCapital,
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }
    if (_capitalSeries == null) {
      return const Center(child: Text('Sin datos de capital'));
    }
    final currency = _kpiSnapshot?.currencyCode ?? 'USD';
    return Stack(
      children: [
        KpiCapitalPanel(
          series: _capitalSeries!,
          preset: _capitalPreset,
          onPresetChanged: _setCapitalPreset,
          currencyCode: currency,
          onRefresh: _loadCapital,
        ),
        if (_capitalLoading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }

  Widget _kpiSkeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 4; i++) ...[
          Container(
            height: i == 0 ? 140 : 110,
            decoration: BoxDecoration(
              color: PosSaleUi.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSalesBody() {
    switch (_controller.status) {
      case DashboardLoadStatus.idle:
      case DashboardLoadStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case DashboardLoadStatus.error:
        return _salesErrorBody();
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
                    'Totales ajustados al día en Venezuela (UTC−4).',
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

  Widget _salesErrorBody() {
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
