import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/api/api_error.dart';
import '../../data/dashboard_repository.dart';
import '../../domain/device_dashboard_payload.dart';

enum DeviceDashboardStatus { idle, loading, success, error, unauthorized, disabled }

class DeviceDashboardController extends ChangeNotifier {
  DeviceDashboardController({
    required DashboardRepository repository,
    required String deviceId,
    required String deviceToken,
    this.refreshInterval = const Duration(seconds: 45),
  }) : _repository = repository,
       _deviceId = deviceId,
       _deviceToken = deviceToken;

  final DashboardRepository _repository;
  final String _deviceId;
  final String _deviceToken;
  final Duration refreshInterval;

  Timer? _timer;
  DeviceDashboardStatus _status = DeviceDashboardStatus.idle;
  DeviceDashboardPayload? _payload;
  String? _message;
  DateTime? _lastUpdatedAt;
  bool _fromCache = false;

  DeviceDashboardStatus get status => _status;
  DeviceDashboardPayload? get payload => _payload;
  String? get message => _message;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  bool get fromCache => _fromCache;

  void startAutoRefresh() {
    _timer?.cancel();
    unawaited(refresh());
    _timer = Timer.periodic(refreshInterval, (_) => unawaited(refresh()));
  }

  void stopAutoRefresh() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    if (_status != DeviceDashboardStatus.success) {
      _status = DeviceDashboardStatus.loading;
      notifyListeners();
    }
    try {
      _payload = await _repository.loadKiosk(
        deviceId: _deviceId,
        deviceToken: _deviceToken,
      );
      _lastUpdatedAt = DateTime.now();
      _fromCache = false;
      _status = DeviceDashboardStatus.success;
      _message = null;
    } on ApiError catch (e) {
      _message = e.userMessage;
      if (e.statusCode == 401) {
        _status = DeviceDashboardStatus.unauthorized;
      } else if (e.statusCode == 403) {
        _status = DeviceDashboardStatus.disabled;
      } else {
        final cached = await _repository.readKioskCache(_deviceId);
        if (cached != null) {
          _payload = cached;
          _fromCache = true;
          _status = DeviceDashboardStatus.success;
        } else {
          _status = DeviceDashboardStatus.error;
        }
      }
    } catch (e) {
      _message = e.toString();
      final cached = await _repository.readKioskCache(_deviceId);
      if (cached != null) {
        _payload = cached;
        _fromCache = true;
        _status = DeviceDashboardStatus.success;
      } else {
        _status = DeviceDashboardStatus.error;
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
