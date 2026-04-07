import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error.dart';
import '../../core/api/stores_api.dart';
import '../../core/config/app_config.dart';
import '../../core/models/business_settings.dart';
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
  });

  final String storeId;
  final StoresApi storesApi;

  @override
  State<StoreAdvancedConfigScreen> createState() =>
      _StoreAdvancedConfigScreenState();
}

class _StoreAdvancedConfigScreenState extends State<StoreAdvancedConfigScreen> {
  late Future<BusinessSettings> _future;
  final _marginCtrl = TextEditingController();
  bool _marginDirty = false;
  bool _savingMargin = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
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
