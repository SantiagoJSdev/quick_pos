import 'package:flutter/material.dart';

import '../../core/api/api_error.dart';
import '../../core/api/suppliers_api.dart';
import '../../core/idempotency/client_mutation_id.dart';
import '../../core/models/local_supplier.dart';
import '../../core/models/supplier.dart';
import '../../core/network/network_errors.dart';
import '../../core/storage/local_prefs.dart';
import '../../core/sync/pending_supplier_mutation_entry.dart';

/// Letras habituales de RIF en Venezuela (personas jurídicas suelen **J**).
const _kRifPrefixChoices = ['J', 'G', 'V', 'E', 'P', 'C'];

/// Alta `POST /suppliers` o edición `PATCH /suppliers/:id` (incl. reactivar con `active`).
class SupplierFormScreen extends StatefulWidget {
  const SupplierFormScreen({
    super.key,
    required this.storeId,
    required this.suppliersApi,
    required this.localPrefs,
    required this.shellOnline,
    this.existing,
  });

  final String storeId;
  final SuppliersApi suppliersApi;
  final LocalPrefs localPrefs;

  /// Desde shell: si es `false`, el guardado va a cola `sync/push` (`SUPPLIER_*`).
  final bool shellOnline;
  final Supplier? existing;

  bool get isEdit => existing != null;

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _rifNumber;
  late final TextEditingController _notes;
  String _rifPrefix = 'J';
  bool _active = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _address = TextEditingController(text: e?.address ?? '');
    _rifNumber = TextEditingController();
    _notes = TextEditingController(text: e?.notes ?? '');
    _active = e?.active ?? true;
    final tid = e?.taxId?.trim();
    if (tid != null && tid.isNotEmpty) {
      final m = RegExp(r'^([A-Za-z])\s*[-]?\s*(.+)$').firstMatch(tid);
      if (m != null) {
        final letter = m.group(1)!.toUpperCase();
        if (_kRifPrefixChoices.contains(letter)) {
          _rifPrefix = letter;
        }
        _rifNumber.text = m.group(2)!.trim();
      } else {
        _rifNumber.text = tid;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _rifNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  String? _optOrNull(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  /// `taxId` en API: `J-12345678-9` (tipo + guion + cuerpo numérico).
  String? _composeTaxId() {
    final n = _rifNumber.text.trim();
    if (n.isEmpty) return null;
    return '$_rifPrefix-$n';
  }

  Map<String, dynamic> _createBody() {
    final body = <String, dynamic>{'name': _name.text.trim()};
    final p = _optOrNull(_phone);
    final em = _optOrNull(_email);
    final ad = _optOrNull(_address);
    final tx = _composeTaxId();
    final no = _optOrNull(_notes);
    if (p != null) body['phone'] = p;
    if (em != null) body['email'] = em;
    if (ad != null) body['address'] = ad;
    if (tx != null) body['taxId'] = tx;
    if (no != null) body['notes'] = no;
    return body;
  }

  Map<String, dynamic> _editBody() {
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'active': _active,
    };
    final p = _optOrNull(_phone);
    final em = _optOrNull(_email);
    final ad = _optOrNull(_address);
    final tx = _composeTaxId();
    final no = _optOrNull(_notes);
    if (p != null) body['phone'] = p;
    if (em != null) body['email'] = em;
    if (ad != null) body['address'] = ad;
    if (tx != null) body['taxId'] = tx;
    if (no != null) body['notes'] = no;
    return body;
  }

  bool get _useOfflineQueueFirst => !widget.shellOnline;

  bool _shouldQueueAfterApiError(ApiError e) =>
      widget.shellOnline && shouldTreatAsOfflineQueueable(e);

  Map<String, dynamic> _syncCreateSupplierMap(String clientSupplierId) {
    final m = <String, dynamic>{
      'clientSupplierId': clientSupplierId,
      'name': _name.text.trim(),
    };
    final p = _optOrNull(_phone);
    final em = _optOrNull(_email);
    final ad = _optOrNull(_address);
    final tx = _composeTaxId();
    final no = _optOrNull(_notes);
    if (p != null) m['phone'] = p;
    if (em != null) m['email'] = em;
    if (ad != null) m['address'] = ad;
    if (tx != null) m['taxId'] = tx;
    if (no != null) m['notes'] = no;
    return m;
  }

  Map<String, dynamic> _syncUpdateSupplierMap() {
    return <String, dynamic>{
      'supplierId': widget.existing!.id,
      ..._editBody(),
    };
  }

  Future<void> _enqueueSupplierMutation() async {
    final ts = DateTime.now().toUtc().toIso8601String();
    final opId = ClientMutationId.newId();
    if (widget.isEdit) {
      await widget.localPrefs.appendPendingSupplierMutation(
        PendingSupplierMutationEntry(
          opId: opId,
          storeId: widget.storeId,
          opTimestampIso: ts,
          opType: 'SUPPLIER_UPDATE',
          supplier: _syncUpdateSupplierMap(),
        ),
      );
      await widget.localPrefs.upsertLocalSupplier(
        LocalSupplier(id: widget.existing!.id, name: _name.text.trim()),
      );
    } else {
      final clientSupplierId = ClientMutationId.newId();
      await widget.localPrefs.appendPendingSupplierMutation(
        PendingSupplierMutationEntry(
          opId: opId,
          storeId: widget.storeId,
          opTimestampIso: ts,
          opType: 'SUPPLIER_CREATE',
          supplier: _syncCreateSupplierMap(clientSupplierId),
        ),
      );
      await widget.localPrefs.upsertLocalSupplier(
        LocalSupplier(id: clientSupplierId, name: _name.text.trim()),
      );
    }
  }

  Future<void> _saveViaApi() async {
    if (widget.isEdit) {
      await widget.suppliersApi.patchSupplier(
        widget.storeId,
        widget.existing!.id,
        _editBody(),
      );
    } else {
      await widget.suppliersApi.createSupplier(widget.storeId, _createBody());
    }
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'El nombre es obligatorio.');
      return;
    }

    setState(() => _saving = true);
    try {
      if (_useOfflineQueueFirst) {
        await _enqueueSupplierMutation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sin conexión: proveedor en cola. Se enviará con sincronización.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      await _saveViaApi();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (_shouldQueueAfterApiError(e)) {
        await _enqueueSupplierMutation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Guardado en cola: se enviará al recuperar conexión.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = e.userMessageForSupport);
    } catch (e) {
      if (!mounted) return;
      if (shouldTreatAsOfflineQueueable(e)) {
        await _enqueueSupplierMutation();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Guardado en cola; se enviará al sincronizar.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).colorScheme.onSurfaceVariant;
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
              labelText: 'Nombre *',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
            enabled: !_saving,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            enabled: !_saving,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            enabled: !_saving,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            decoration: const InputDecoration(
              labelText: 'Dirección',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
            enabled: !_saving,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'RIF',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _rifPrefix,
                      isExpanded: true,
                      items: _kRifPrefixChoices
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _rifPrefix = v ?? 'J'),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _rifNumber,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Número',
                    hintText: '12345678-9',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Identificador fiscal (RIF): tipo + guion + número, p. ej. J-12345678-9.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: hint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Notas',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            enabled: !_saving,
          ),
          if (widget.isEdit) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Activo'),
              subtitle: const Text(
                'Si está desactivado, no podrás usarlo en recepción de compra '
                'hasta reactivarlo.',
              ),
              value: _active,
              onChanged: _saving ? null : (v) => setState(() => _active = v),
            ),
          ],
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
