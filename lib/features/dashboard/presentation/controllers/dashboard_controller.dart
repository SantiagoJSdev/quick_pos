import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/api/api_error.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/dashboard_filters.dart';

enum DashboardLoadStatus { idle, loading, success, error }

class DashboardController extends ChangeNotifier {
  DashboardController({
    required DashboardRepository repository,
    required String storeId,
    DashboardFilters initialFilters = const DashboardFilters.today(),
  }) : _repository = repository,
       _storeId = storeId,
       _filters = initialFilters;

  final DashboardRepository _repository;
  final String _storeId;

  DashboardLoadStatus _status = DashboardLoadStatus.idle;
  DashboardHomeData? _data;
  ApiError? _error;
  String? _message;
  DashboardFilters _filters;

  DashboardLoadStatus get status => _status;
  DashboardHomeData? get data => _data;
  ApiError? get error => _error;
  String? get message => _message;
  DashboardFilters get filters => _filters;

  Future<void> load({DashboardFilters? filters}) async {
    if (filters != null) _filters = filters;
    _status = DashboardLoadStatus.loading;
    _error = null;
    _message = null;
    notifyListeners();
    try {
      _data = await _repository.loadHome(_storeId, _filters);
      _status = DashboardLoadStatus.success;
    } on ApiError catch (e) {
      _error = e;
      _message = e.userMessage;
      _status = DashboardLoadStatus.error;
    } catch (e) {
      _message = e.toString();
      _status = DashboardLoadStatus.error;
    }
    notifyListeners();
  }

  void setFilters(DashboardFilters filters) {
    if (_filters == filters) return;
    _filters = filters;
    unawaited(load());
  }
}
