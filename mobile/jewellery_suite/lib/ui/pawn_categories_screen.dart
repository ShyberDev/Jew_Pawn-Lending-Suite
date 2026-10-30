import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'palette.dart';
import 'widgets.dart';

/// Pawn Loans → Categories → Manage.
///
/// The shop asked for three kinds of grouping on a pledge: Active / Released,
/// Villages, and **Categories** — starting with Forgot_Slip_List and
/// Pawn_Removed and open to custom names ("Add Custom"). Names can be renamed
/// later; renaming also updates every loan that carried the old name.
class PawnCategoriesScreen extends StatefulWidget {
  const PawnCategoriesScreen({super.key});

  @override
  State<PawnCategoriesScreen> createState() => _PawnCategoriesScreenState();
}

class _PawnCategoriesScreenState extends State<PawnCategoriesScreen> {
  List<String> _names = const [];
  Map<String, int> _counts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final names = await state.pawnCategories();
    final loans = await state.db.query('pawn_loans', columns: ['category']);
    final counts = <String, int>{};
    for (final l in loans) {
      final c = l['category']?.toString() ?? '';
      if (c.isEmpty) continue;
      counts[c] = (counts[c] ?? 0) + 1;
    }
    if (!mounted) return;
    setState(() {
      _names = names;
      _counts = counts;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final state = context.read<AppState>();
    final ctl = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New pawn category'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: fieldDecoration('e.g. Forgot_Slip_List'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
                child: const Text('Add')),
          ],
        ),
      );
      if (name == null || name.isEmpty) return;
      await state.addPawnCategory(name);
      await _load();
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      ctl.dispose();
    }
  }

  Future<void> _rename(String from) async {
    final state = context.read<AppState>();
    final ctl = TextEditingController(text: from);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename category'),
          content: TextField(
            controller: ctl,
            autofocus: true,
            decoration: fieldDecoration('Category name'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
                child: const Text('Save')),
          ],
        ),
      );
      if (name == null || name.isEmpty || name == from) return;
      await state.renamePawnCategory(from, name);
      await _load();
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      ctl.dispose();
    }
  }

  Future<void> _delete(String name) async {
    final state = context.read<AppState>();
    final ok = await confirmDialog(
      context,
      'Remove the category "$name"? The pawn loans stay; they simply lose '
      'this label.',
      title: 'Remove category',
    );
    if (!ok || !mounted) return;
    await state.deletePawnCategory(name);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(title: const Text('Pawn Categories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add Custom'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SectionCard(
                  title: 'Categories',
                  children: [
                    if (_names.isEmpty)
                      const Text('No categories yet. Tap Add Custom.'),
                    for (final name in _names)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.label_outline,
                            color: kGoldDark),
                        title: Text(name,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${_counts[name] ?? 0} loan(s)',
                          style: TextStyle(
                              fontSize: 11, color: mutedOf(context)),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) =>
                              v == 'rename' ? _rename(name) : _delete(name),
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'rename',
                                child: Text('Rename / change name')),
                            PopupMenuItem(
                                value: 'delete',
                                child: Text('Remove category')),
                          ],
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Renaming a category also renames it on every pawn loan '
                    'that uses it. Removing one only removes the label.',
                    style: TextStyle(
                        fontSize: 11.5, height: 1.4, color: mutedOf(context)),
                  ),
                ),
                const SizedBox(height: 70),
              ],
            ),
    );
  }
}
