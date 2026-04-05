import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/local_supplier.dart';
import '../../core/storage/local_prefs.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// C2 — alta o edición de nombre (UUID fijo en edición).
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({
    super.key,
    required this.localPrefs,
    this.existing,
    this.existingIds,
  });

  final LocalPrefs localPrefs;
  final LocalSupplier? existing;

  /// IDs ya usados (para validar duplicado en alta).
  final Set<String>? existingIds;

  bool get isEdit => existing != null;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _id;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _id = TextEditingController(text: e?.id ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _id.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final name = _name.text.trim();
    final id = _id.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }
    if (!widget.isEdit) {
      if (id.isEmpty) {
        setState(() => _error = 'Pegá el UUID del proveedor (seed / Postman / admin).');
        return;
      }
      if (!_uuidPattern.hasMatch(id)) {
        setState(() => _error = 'El UUID no tiene formato válido (ej. 550e8400-e29b-41d4-a716-446655440000).');
        return;
      }
      final taken = widget.existingIds?.contains(id.toLowerCase()) ?? false;
      if (taken) {
        setState(() => _error = 'Ya existe un proveedor con ese UUID.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final list = await widget.localPrefs.getLocalSuppliers();
      final supplier = LocalSupplier(
        id: widget.isEdit ? widget.existing!.id : id,
        name: name,
      );
      if (widget.isEdit) {
        final i = list.indexWhere((s) => s.id == widget.existing!.id);
        if (i >= 0) {
          list[i] = supplier;
        } else {
          list.add(supplier);
        }
      } else {
        list.add(supplier);
      }
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      await widget.localPrefs.saveLocalSuppliers(list);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Editar proveedor' : 'Nuevo proveedor'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            enabled: !_saving,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _id,
            decoration: const InputDecoration(
              labelText: 'UUID del proveedor',
              hintText: 'Pegar desde seed, Prisma Studio o Postman',
              border: OutlineInputBorder(),
            ),
            enabled: !widget.isEdit && !_saving,
            autocorrect: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F\-]')),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'No hay API de proveedores: este UUID es el que usará la app en '
            'compras (`POST /purchases`) cuando implementemos ese módulo.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
