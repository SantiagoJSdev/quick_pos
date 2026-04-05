import 'package:flutter/material.dart';

import '../../core/models/local_supplier.dart';
import '../../core/storage/local_prefs.dart';
import 'supplier_form_screen.dart';

/// C1 — lista local de proveedores (nombre + UUID).
class SuppliersListScreen extends StatefulWidget {
  const SuppliersListScreen({super.key, required this.localPrefs});

  final LocalPrefs localPrefs;

  @override
  State<SuppliersListScreen> createState() => _SuppliersListScreenState();
}

class _SuppliersListScreenState extends State<SuppliersListScreen> {
  List<LocalSupplier> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await widget.localPrefs.getLocalSuppliers();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  Future<void> _openForm({LocalSupplier? existing}) async {
    final ids = _list.map((e) => e.id.toLowerCase()).toSet();
    if (existing != null) ids.remove(existing.id.toLowerCase());
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => SupplierFormScreen(
          localPrefs: widget.localPrefs,
          existing: existing,
          existingIds: existing == null ? ids : null,
        ),
      ),
    );
    if (ok == true && mounted) await _load();
  }

  Future<void> _confirmDelete(LocalSupplier s) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar proveedor'),
        content: Text('¿Eliminar "${s.name}" de la lista local?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final next = _list.where((e) => e.id != s.id).toList();
    await widget.localPrefs.saveLocalSuppliers(next);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proveedores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No hay proveedores guardados en este dispositivo.\n\n'
                      'Usá + para pegar el UUID del seed o del admin. '
                      'En compras usaremos ese id con el API.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _list.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final s = _list[i];
                    return ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                        s.id,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      onTap: () => _openForm(existing: s),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'delete') _confirmDelete(s);
                        },
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 'delete', child: Text('Quitar de la lista')),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Proveedor'),
      ),
    );
  }
}
