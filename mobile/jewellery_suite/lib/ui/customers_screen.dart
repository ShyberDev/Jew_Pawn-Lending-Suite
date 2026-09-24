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
  const CustomerForm({super.key, this.existing});

  final Map<String, Object?>? existing;

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
  late final TextEditingController _gold;
  late final TextEditingController _silver;
  late final TextEditingController _khatabook;
  late final TextEditingController _notes;
  String _type = 'General';
  String _rating = 'New';
  String _idType = 'Aadhaar';
  String? _village;
  String? _photo;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _uuid = (e?['client_uuid'] as String?) ?? newUuid();
    _name = TextEditingController(text: e?['customer_name']?.toString());
    _phone = TextEditingController(text: e?['phone']?.toString());
    _address = TextEditingController(text: e?['address']?.toString());
    _idNumber = TextEditingController(text: e?['id_proof_number']?.toString());
    _gold = TextEditingController(text: e?['gold_interest_rate']?.toString());
    _silver = TextEditingController(text: e?['silver_interest_rate']?.toString());
    _khatabook =
        TextEditingController(text: e?['khatabook_interest_rate']?.toString());
    _notes = TextEditingController(text: e?['notes']?.toString());
    _type = (e?['customer_type'] as String?) ?? 'General';
    _rating = (e?['rating'] as String?) ?? 'New';
    _idType = (e?['id_proof_type'] as String?) ?? 'Aadhaar';
    _village = e?['village'] as String?;
    _photo = e?['photo_path'] as String?;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _phone,
      _address,
      _idNumber,
      _gold,
      _silver,
      _khatabook,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) =>
      c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

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
      'rating': _rating,
      'gold_interest_rate': _num(_gold),
      'silver_interest_rate': _num(_silver),
      'khatabook_interest_rate': _num(_khatabook),
      'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      'status': 'Active',
    };
    await state.saveEntity(
        table: 'customers', doctype: 'Pawn Customer', uuid: _uuid, data: data);
    if (_photo != null && _photo!.isNotEmpty) {
      await state.savePhoto(
          table: 'customers',
          doctype: 'Pawn Customer',
          uuid: _uuid,
          path: _photo!);
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
              DropdownButtonFormField<String>(
                value: _type,
                decoration: fieldDecoration('Customer type'),
                items: const ['Gold Pawn', 'Silver Pawn', 'Khatabook', 'General']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
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
            SectionCard(title: 'ID & rating', children: [
              DropdownButtonFormField<String>(
                value: _idType,
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _rating,
                decoration: fieldDecoration('Rating'),
                items: const ['New', 'Good', 'Bad']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) => setState(() => _rating = v ?? _rating),
              ),
            ]),
            SectionCard(title: 'Interest overrides (% / month)', children: [
              Row(children: [
                Expanded(
                    child: TextFormField(
                  controller: _gold,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration('Gold'),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  controller: _silver,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration('Silver'),
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  controller: _khatabook,
                  keyboardType: TextInputType.number,
                  decoration: fieldDecoration('Khatabook'),
                )),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                controller: _notes,
                maxLines: 2,
                decoration: fieldDecoration('Notes'),
              ),
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
          value: value,
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
