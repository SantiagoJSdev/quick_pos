import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/api_client.dart';
import '../../core/api/stores_api.dart';
import '../../core/config/app_config.dart';
import '../../core/network/backend_origin_resolver.dart';
import '../../core/models/business_settings.dart';
import '../../core/storage/local_prefs.dart';
import '../sale/pos_sale_ui_tokens.dart';

final _marginDecimal = RegExp(r'^\d+(\.\d+)?$');

bool _validStoreMarginPercent(String raw) {
  if (!_marginDecimal.hasMatch(raw.trim())) return false;
  final v = double.tryParse(raw.trim());
  if (v == null) return false;
  return v >= 0 && v <= 999;
}

/// Pide la clave definida en [AppConfig.effectiveConfigAdminPin] (`CONFIG_ADMIN_PIN` / `dart-define`).
Future<bool> showStoreConfigPinDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => const _StoreConfigPinDialog(),
  );
  return ok == true;
}

class _StoreConfigPinDialog extends StatefulWidget {
  const _StoreConfigPinDialog();

  @override
  State<_StoreConfigPinDialog> createState() => _StoreConfigPinDialogState();
}

class _StoreConfigPinDialogState extends State<_StoreConfigPinDialog> {
  late final TextEditingController _ctrl;
  bool _obscure = true;
  String _err = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _trySubmit() {
    if (AppConfig.adminPinMatches(_ctrl.text)) {
      Navigator.pop(context, true);
    } else {
      setState(() => _err = 'Clave incorrecta.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Configuración de tienda'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ingresá la clave de administración para ver el ID de la '
            'tienda y el margen por defecto.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              labelText: 'Clave',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Mostrar clave' : 'Ocultar clave',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _trySubmit(),
          ),
          if (_err.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _err,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _trySubmit,
          child: const Text('Entrar'),
        ),
      ],
    );
  }
}

/// Pantalla tras validar clave: ID de tienda + margen por defecto (PATCH business-settings).
class StoreAdvancedConfigScreen extends StatefulWidget {
  const StoreAdvancedConfigScreen({
    super.key,
    required this.storeId,
    required this.storesApi,
    required this.localPrefs,
  });

  final String storeId;
  final StoresApi storesApi;
  final LocalPrefs localPrefs;

  @override
  State<StoreAdvancedConfigScreen> createState() =>
      _StoreAdvancedConfigScreenState();
}

class _StoreAdvancedConfigScreenState extends State<StoreAdvancedConfigScreen> {
  late Future<BusinessSettings> _future;
  final _marginCtrl = TextEditingController();
  final _apiUrlCtrl = TextEditingController();
  bool _marginDirty = false;
  bool _savingMargin = false;
  bool _savingApiUrl = false;
  bool _testingApiUrl = false;
  bool _cloudResolverBusy = false;
  String? _apiConnectionStatus;
  bool _apiConnectionOk = false;
  String _selectedProfile = '';
  DateTime? _resolverUpdatedAt;

  @override
  void initState() {
    super.initState();
    _future = _load();
    final initial = AppConfig.effectiveApiBaseUrl;
    _apiUrlCtrl.text = initial;
    _selectedProfile = _detectProfile(initial);
    _loadResolverMeta();
  }

  Future<void> _loadResolverMeta() async {
    final at = await widget.localPrefs.getPersistedApiOriginUpdatedAt();
    if (!mounted) return;
    setState(() => _resolverUpdatedAt = at);
  }

  Future<BusinessSettings> _load() async {
    final s = await widget.storesApi.getBusinessSettings(widget.storeId);
    if (mounted && !_marginDirty) {
      _marginCtrl.text = s.defaultMarginPercent?.trim() ?? '';
    }
    return s;
  }

  @override
  void dispose() {
    _marginCtrl.dispose();
    _apiUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _marginDirty = false;
      _future = _load();
    });
    await _future;
  }

  Future<void> _saveMargin() async {
    final raw = _marginCtrl.text.trim();
    if (!_validStoreMarginPercent(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usá un número entre 0 y 999 (ej. 15 o 20.5).'),
        ),
      );
      return;
    }
    setState(() => _savingMargin = true);
    try {
      await widget.storesApi.patchBusinessSettings(
        widget.storeId,
        {'defaultMarginPercent': raw},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Margen de tienda actualizado')),
      );
      await _refresh();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _savingMargin = false);
    }
  }

  bool _looksLikeApiUrl(String raw) {
    final normalized = AppConfig.normalizeApiBaseUrl(raw);
    if (normalized.isEmpty) return false;
    final uri = Uri.tryParse(normalized);
    if (uri == null) return false;
    final s = uri.scheme.toLowerCase();
    if (s != 'http' && s != 'https') return false;
    if (uri.host.trim().isEmpty) return false;
    return true;
  }

  String _detectProfile(String rawUrl) {
    final normalized = AppConfig.normalizeApiBaseUrl(rawUrl);
    final uri = Uri.tryParse(normalized);
    final host = (uri?.host ?? '').toLowerCase().trim();
    if (host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2') {
      return 'LOCAL';
    }
    if (_isPrivateLanHost(host)) return 'LAN';
    return 'PROD';
  }

  bool _isPrivateLanHost(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return false;
    final a = nums[0]!;
    final b = nums[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  String _buildProfileUrl(String profile) {
    final current = Uri.tryParse(AppConfig.normalizeApiBaseUrl(_apiUrlCtrl.text));
    final pathRaw = (current?.path ?? '/api/v1').trim();
    final currentPath = pathRaw.isEmpty
        ? '/api/v1'
        : (pathRaw.startsWith('/') ? pathRaw : '/$pathRaw');
    final portSuffix = (current?.hasPort ?? false) ? ':${current!.port}' : ':3002';
    switch (profile) {
      case 'LOCAL':
        return 'http://10.0.2.2$portSuffix$currentPath';
      case 'LAN':
        return 'http://192.168.0.190$portSuffix$currentPath';
      case 'PROD':
      default:
        return AppConfig.normalizeApiBaseUrl(AppConfig.apiBaseUrl);
    }
  }

  void _applyProfile(String profile) {
    final next = _buildProfileUrl(profile);
    setState(() {
      _selectedProfile = profile;
      _apiUrlCtrl.text = next;
      _apiConnectionStatus = null;
      _apiConnectionOk = false;
    });
  }

  Future<void> _saveApiUrl() async {
    final raw = _apiUrlCtrl.text.trim();
    if (!_looksLikeApiUrl(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'URL inválida. Usá http(s)://host[:puerto]/api/v1',
          ),
        ),
      );
      return;
    }
    final normalized = AppConfig.normalizeApiBaseUrl(raw);
    setState(() => _savingApiUrl = true);
    try {
      await widget.localPrefs.setApiBaseUrlOverride(
        normalized,
        followCloudResolver: false,
      );
      AppConfig.setRuntimeApiBaseUrlOverride(normalized);
      if (!mounted) return;
      _apiUrlCtrl.text = normalized;
      _selectedProfile = _detectProfile(normalized);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL de backend guardada. Se usa en próximas llamadas.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _savingApiUrl = false);
    }
  }

  Future<void> _runApiConnectionTest({bool saveOverrideOnSuccess = false}) async {
    final raw = _apiUrlCtrl.text.trim();
    if (!_looksLikeApiUrl(raw)) {
      setState(() {
        _apiConnectionOk = false;
        _apiConnectionStatus =
            'URL inválida. Usá http(s)://host[:puerto]/api/v1';
      });
      return;
    }
    final normalized = AppConfig.normalizeApiBaseUrl(raw);
    setState(() {
      _testingApiUrl = true;
      _apiConnectionStatus = null;
      _apiConnectionOk = false;
    });
    final testClient = ApiClient(baseUrl: normalized);
    try {
      final testStoresApi = StoresApi(testClient);
      await testStoresApi.getBusinessSettings(widget.storeId);
      if (!mounted) return;
      setState(() {
        _apiConnectionOk = true;
        _apiConnectionStatus = saveOverrideOnSuccess
            ? 'Conexión OK. URL guardada.'
            : 'Conexión OK. Se pudo leer business-settings.';
      });
      if (saveOverrideOnSuccess) {
        await widget.localPrefs.setApiBaseUrlOverride(
          normalized,
          followCloudResolver: true,
        );
        if (!mounted) return;
        AppConfig.setRuntimeApiBaseUrlOverride(normalized);
        _apiUrlCtrl.text = normalized;
        _selectedProfile = _detectProfile(normalized);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL de backend guardada (verificada con la nube).'),
          ),
        );
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() {
        _apiConnectionOk = false;
        _apiConnectionStatus = e.userMessageForSupport;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _apiConnectionOk = false;
        _apiConnectionStatus = e.toString();
      });
    } finally {
      testClient.close();
      if (mounted) setState(() => _testingApiUrl = false);
    }
  }

  Future<void> _testApiUrl() => _runApiConnectionTest();

  Future<void> _fetchFromCloudAndProbe() async {
    setState(() {
      _cloudResolverBusy = true;
      _apiConnectionStatus = null;
      _apiConnectionOk = false;
    });
    try {
      final r = await BackendOriginResolver().fetchFromVercel();
      if (!mounted) return;
      String? origin;
      DateTime? resolverAt;
      if (r != null) {
        await widget.localPrefs.setPersistedApiOrigin(r.baseUrl, r.updatedAt);
        if (!mounted) return;
        origin = r.baseUrl;
        resolverAt = r.updatedAt;
      } else {
        origin = await widget.localPrefs.getPersistedApiOrigin();
        resolverAt = await widget.localPrefs.getPersistedApiOriginUpdatedAt();
        if (!mounted) return;
        if (origin == null || origin.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Vercel no respondió y no hay origen guardado. Probá de nuevo o '
                'configurá la URL a mano.',
              ),
            ),
          );
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Vercel no respondió; se probó el último origen guardado en el equipo.',
            ),
          ),
        );
      }
      final apiV1 = apiV1BaseFromOrigin(origin);
      if (apiV1.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Respuesta del resolver inválida.')),
        );
        return;
      }
      setState(() {
        _resolverUpdatedAt = resolverAt;
        _apiUrlCtrl.text = apiV1;
        _selectedProfile = _detectProfile(apiV1);
      });
      await _runApiConnectionTest(saveOverrideOnSuccess: true);
    } finally {
      if (mounted) setState(() => _cloudResolverBusy = false);
    }
  }

  Future<void> _resetApiUrlDefault() async {
    setState(() => _savingApiUrl = true);
    try {
      await widget.localPrefs.clearApiBaseUrlOverride();
      AppConfig.setRuntimeApiBaseUrlOverride(null);
      if (!mounted) return;
      _apiUrlCtrl.text = AppConfig.effectiveApiBaseUrl;
      _selectedProfile = _detectProfile(_apiUrlCtrl.text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL restablecida al valor por defecto de compilación.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _savingApiUrl = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: PosSaleUi.bg,
      ),
      child: Scaffold(
        backgroundColor: PosSaleUi.bg,
        appBar: AppBar(
          title: const Text('Configuración de tienda'),
          backgroundColor: PosSaleUi.surface,
          foregroundColor: PosSaleUi.text,
        ),
        body: FutureBuilder<BusinessSettings>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final err = snapshot.error;
              String msg = err.toString();
              if (err is ApiError) msg = err.userMessageForSupport;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(msg, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _refresh,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final s = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text(
                  'ID de la tienda',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: PosSaleUi.text,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mismo valor que usa el API (`storeId`). Copialo para soporte o integraciones.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PosSaleUi.textMuted,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  color: PosSaleUi.surface3,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            widget.storeId,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontFamily: 'monospace',
                                  color: PosSaleUi.text,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copiar',
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: widget.storeId),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('ID de tienda copiado'),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 20),
                          color: PosSaleUi.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Margen por defecto',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: PosSaleUi.text,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Porcentaje sobre costo para sugerir precio de lista (0–999). '
                  'Se aplica a productos en modo «Margen de la tienda».',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PosSaleUi.textMuted,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _marginCtrl,
                  onChanged: (_) => _marginDirty = true,
                  decoration: const InputDecoration(
                    labelText: 'Margen %',
                    hintText: 'ej. 15',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _savingMargin ? null : _saveMargin,
                  child: _savingMargin
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar margen'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Conexión backend',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: PosSaleUi.text,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Cambiá la URL base del API para este dispositivo sin recompilar '
                  '(ej. red LAN para APK en móvil).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PosSaleUi.textMuted,
                        height: 1.35,
                      ),
                ),
                if (_resolverUpdatedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Origen automático (Vercel): última respuesta '
                    '${_resolverUpdatedAt!.toUtc().toIso8601String()}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: PosSaleUi.textFaint,
                          height: 1.35,
                          fontSize: 11,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: (_savingApiUrl ||
                          _testingApiUrl ||
                          _cloudResolverBusy)
                      ? null
                      : _fetchFromCloudAndProbe,
                  icon: _cloudResolverBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download_outlined, size: 20),
                  label: Text(
                    _cloudResolverBusy
                        ? 'Consultando Vercel…'
                        : 'Actualizar desde la nube (Vercel)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiUrlCtrl,
                  onChanged: (v) {
                    setState(() => _selectedProfile = _detectProfile(v));
                  },
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Base URL API',
                    hintText: 'http://192.168.0.190:3002/api/v1',
                    border: OutlineInputBorder(),
                    filled: true,
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Producción'),
                      selected: _selectedProfile == 'PROD',
                      onSelected: (_savingApiUrl ||
                              _testingApiUrl ||
                              _cloudResolverBusy)
                          ? null
                          : (_) => _applyProfile('PROD'),
                    ),
                    ChoiceChip(
                      label: const Text('LAN'),
                      selected: _selectedProfile == 'LAN',
                      onSelected: (_savingApiUrl ||
                              _testingApiUrl ||
                              _cloudResolverBusy)
                          ? null
                          : (_) => _applyProfile('LAN'),
                    ),
                    ChoiceChip(
                      label: const Text('Local (emulador)'),
                      selected: _selectedProfile == 'LOCAL',
                      onSelected: (_savingApiUrl ||
                              _testingApiUrl ||
                              _cloudResolverBusy)
                          ? null
                          : (_) => _applyProfile('LOCAL'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (_savingApiUrl ||
                                _testingApiUrl ||
                                _cloudResolverBusy)
                            ? null
                            : _testApiUrl,
                        child: _testingApiUrl
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Probar conexión'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: (_savingApiUrl ||
                                _testingApiUrl ||
                                _cloudResolverBusy)
                            ? null
                            : _saveApiUrl,
                        child: _savingApiUrl
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Guardar URL'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: (_savingApiUrl ||
                                _testingApiUrl ||
                                _cloudResolverBusy)
                            ? null
                            : _resetApiUrlDefault,
                        child: const Text('Usar default'),
                      ),
                    ),
                  ],
                ),
                if (_apiConnectionStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _apiConnectionStatus!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _apiConnectionOk ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Text(
                  'Tienda: ${s.storeName}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PosSaleUi.textFaint,
                      ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
