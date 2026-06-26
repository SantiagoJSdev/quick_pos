import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/api/api_error.dart';
import '../../../../core/pos/pos_terminal_info.dart';
import '../../../../core/storage/local_prefs.dart';
import '../../../sale/pos_sale_ui_tokens.dart';
import '../../data/dashboard_repository.dart';

/// Admin: activar modo kiosk y guardar token (una sola vez en respuesta PATCH).
class DeviceDashboardSetupScreen extends StatefulWidget {
  const DeviceDashboardSetupScreen({
    super.key,
    required this.repository,
    required this.storeId,
    required this.localPrefs,
  });

  final DashboardRepository repository;
  final String storeId;
  final LocalPrefs localPrefs;

  @override
  State<DeviceDashboardSetupScreen> createState() =>
      _DeviceDashboardSetupScreenState();
}

class _DeviceDashboardSetupScreenState extends State<DeviceDashboardSetupScreen> {
  final _pinCtrl = TextEditingController();
  bool _busy = false;
  String? _deviceId;
  String? _tokenShown;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadDeviceId());
  }

  Future<void> _loadDeviceId() async {
    final info = await PosTerminalInfo.load(widget.localPrefs);
    if (!mounted) return;
    setState(() => _deviceId = info.deviceId);
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final pin = _pinCtrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'Ingresá el PIN del servidor.');
      return;
    }
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) {
      setState(() => _error = 'deviceId no disponible.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final config = await widget.repository.activateKioskMode(
        storeId: widget.storeId,
        deviceId: deviceId,
        adminPin: pin,
      );
      if (!mounted) return;
      setState(() {
        _tokenShown = config.dashboardAccessToken;
        _busy = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosSaleUi.bg,
      appBar: AppBar(title: const Text('Configurar dashboard TV')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Convierte este terminal en modo kiosk (solo lectura). El token '
            'solo se muestra una vez al activar.',
            style: TextStyle(color: PosSaleUi.textMuted, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (_deviceId != null) ...[
            Text(
              'deviceId de instalación',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: PosSaleUi.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _deviceId!,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: PosSaleUi.text,
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: _deviceId!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('deviceId copiado')),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copiar'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _pinCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'PIN del servidor (DASHBOARD_ADMIN_PIN)',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: PosSaleUi.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _activate,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Activar modo dashboard'),
          ),
          if (_tokenShown != null && _tokenShown!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              'Token de acceso (guardar ahora)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: PosSaleUi.gold,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              _tokenShown!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: PosSaleUi.text,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'El token quedó guardado en este dispositivo. Reiniciá la app '
              'para entrar en modo TV si el servidor marcó deviceMode=DASHBOARD.',
              style: TextStyle(color: PosSaleUi.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
