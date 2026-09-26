import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/ids.dart';
import 'widgets.dart';

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _search = '';

  Future<List<Map<String, Object?>>> _load() {
    final state = context.read<AppState>();
    if (_search.trim().isEmpty) {
      return state.db.query('customers', orderBy: 'customer_name asc');
    }
    final term = '%${_search.trim()}%';
    return state.db.query('customers',
        where: 'customer_name LIKE ? OR phone LIKE ?',
        whereArgs: [term, term],
        orderBy: 'customer_name asc');
  }

  Future<void> _openForm([Map<String, Object?>? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => CustomerForm(existing: existing)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Customers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              decoration: fieldDecoration('Search name or phone'),
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: _load(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final rows = snapshot.data!;
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('No customers yet. Tap New to add one.'));
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final photo = row['photo_path'] as String?;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: (photo != null &&
                                photo.isNotEmpty &&
                                File(photo).existsSync())
                            ? FileImage(File(photo))
                            : null,
                        child: (photo == null || photo.isEmpty)
                            ? Text((row['customer_name'] ?? '?')
                                .toString()
                                .characters
                                .first
                                .toUpperCase())
                            : null,
                      ),
                      title: Text(row['customer_name']?.toString() ?? '-'),
                      subtitle: Text([
                        if (row['phone'] != null) row['phone'].toString(),
                        if (row['village'] != null) row['village'].toString(),
                      ].join(' · ')),
                      trailing: row['server_name'] == null
                          ? const Icon(Icons.cloud_upload_outlined, size: 18)
                          : null,
                      onTap: () => _openForm(row),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerForm extends StatefulWidget {
  const CustomerForm(
      {super.key, this.existing, this.initialVillage, this.initialType});

  final Map<String, Object?>? existing;
  final String? initialVillage;
  final String? initialType;

  @override
  State<CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final String _uuid;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _idNumber;
  late final TextEditingController _customerId;
  String _type = 'General';
  String _idType = 'Aadhaar';
  String? _village;
  String? _photo;
  String? _idFront;
  String? _idBack;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _uuid = (e?['client_uuid'] as String?) ?? newUuid();
    _name = TextEditingController(text: e?['customer_name']?.toString());
    _phone = TextEditingController(text: e?['phone']?.toString());
    _address = TextEditingController(text: e?['address']?.toString());
    _idNumber = TextEditingController(text: e?['id_proof_number']?.toString());
    _customerId = TextEditingController(text: e?['customer_id']?.toString());
    _type = (e?['customer_type'] as String?) ?? widget.initialType ?? 'General';
    _idType = (e?['id_proof_type'] as String?) ?? 'Aadhaar';
    _village = (e?['village'] as String?) ?? widget.initialVillage;
    _photo = e?['photo_path'] as String?;
    _idFront = e?['id_photo_front'] as String?;
    _idBack = e?['id_photo_back'] as String?;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _idNumber, _customerId]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final state = context.read<AppState>();
    final data = <String, Object?>{
      'customer_name': _name.text.trim(),
      'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      'customer_type': _type,
      'village': _village,
      'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
      'id_proof_type': _idType,
      'id_proof_number':
          _idNumber.text.trim().isEmpty ? null : _idNumber.text.trim(),
      'id_photo_front': _idFront,
      'id_photo_back': _idBack,
      'status': 'Active',
    };
    if (widget.existing == null) {
      // v1.0.9+: book scheme (A-01 … Z-99 → A-001 …). A typed ID is used
      // as-is and the next customer continues from it; blank = next in the book.
      try {
        data['customer_id'] =
            await state.claimCustomerId(_customerId.text);
      } on StateError catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
    } else {
      // Editable ID: if the number changed, free the old one (reusable) and
      // re-seed the auto sequence from the new one.
      final oldId = widget.existing!['customer_id']?.toString() ?? '';
      final newId = _customerId.text.trim();
      if (newId.isNotEmpty && newId != oldId) {
        try {
          data['customer_id'] =
              await state.claimCustomerId(newId, excludeUuid: _uuid);
        } on StateError catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(e.message)));
          }
          return;
        }
        await state.freeCustomerId(oldId);
      }
    }
    await state.saveEntity(
        table: 'customers', doctype: 'Pawn Customer', uuid: _uuid, data: data);
    for (final entry in {
      'photo_path': (_photo, 'photo_path'),
      'id_photo_front': (_idFront, 'id_photo_front'),
      'id_photo_back': (_idBack, 'id_photo_back'),
    }.entries) {
      final path = entry.value.$1;
      final column = entry.value.$2;
      if (path != null && path.isNotEmpty) {
        await state.savePhoto(
            table: 'customers',
            doctype: 'Pawn Customer',
            uuid: _uuid,
            path: path,
            column: column);
      }
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _addVillage() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New village'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: fieldDecoration('Village name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Add')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final state = context.read<AppState>();
    await state.saveEntity(
      table: 'villages',
      doctype: 'Village',
      uuid: newUuid(),
      data: {'village_name': name},
    );
    if (mounted) setState(() => _village = name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New Customer' : 'Edit Customer'),
        actions: [
          TextButton(onPressed: _save, child: const Text('SAVE')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SectionCard(title: 'Identity', children: [
              PhotoField(
                  path: _photo,
                  onPicked: (path) => setState(() => _photo = path)),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: fieldDecoration('Customer name *'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: fieldDecoration('Phone'),
              ),
              const SizedBox(height: 10),
              // v1.0.9+: customer ID — book scheme A-01, A-02 … Z-99, then
              // A-001 … Typed ID is used as-is and the sequence continues from
              // it; blank = next ID in the book.
              TextFormField(
                controller: _customerId,
                textCapitalization: TextCapitalization.characters,
                decoration: fieldDecoration(
                  'Customer ID',
                  hint: widget.existing == null
                      ? 'Leave blank for next ID (A-01)'
                      : 'Change ID',
                ),
              ),
              if (widget.existing == null) ...[
                const SizedBox(height: 4),
                const Text(
                  'Book numbers: A-01, A-02 … A-99, B-01 … Z-99, then A-001… '
                  'Type an ID to start from it (e.g. C-07 → next C-08).',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF8A6D14)),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _villageDropdown()),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add village',
                    onPressed: _addVillage,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                maxLines: 2,
                decoration: fieldDecoration('Address'),
              ),
            ]),
            SectionCard(title: 'ID proof', children: [
              DropdownButtonFormField<String>(
                initialValue: _idType,
                decoration: fieldDecoration('ID proof type'),
                items: const ['Aadhaar', 'Voter ID', 'PAN', 'Driving License', 'Other']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _idType = v ?? _idType),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _idNumber,
                decoration: fieldDecoration('ID proof number'),
              ),
              const SizedBox(height: 12),
              Text('ID photo — front',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              PhotoField(
                  label: 'ID front',
                  path: _idFront,
                  onPicked: (path) => setState(() => _idFront = path)),
              const SizedBox(height: 12),
              Text('ID photo — back',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              PhotoField(
                  label: 'ID back',
                  path: _idBack,
                  onPicked: (path) => setState(() => _idBack = path)),
            ]),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _villageDropdown() {
    final db = context.read<AppState>().db;
    return FutureBuilder<List<Map<String, Object?>>>(
      future: db.query('villages', orderBy: 'village_name asc'),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const [];
        final names = rows
            .map((r) => r['village_name']?.toString())
            .whereType<String>()
            .toList();
        final value = (_village != null && names.contains(_village)) ? _village : null;
        return DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: fieldDecoration('Village'),
          items: names
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: (v) => setState(() => _village = v),
        );
      },
    );
  }
}
