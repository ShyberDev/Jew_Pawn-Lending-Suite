import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'admin_guard.dart';
import 'palette.dart';
import 'widgets.dart';

/// Home → System → Password Settings.
///
/// One master switch plus one toggle per destructive action (built from the
/// [adminGatedActions] registry, so a newly gated action appears here with no
/// UI work). A password is asked only when the master AND that action's toggle
/// are both on. The password itself can be viewed/changed here after typing
/// the current one.
class PasswordSettingsScreen extends StatefulWidget {
  const PasswordSettingsScreen({super.key});

  @override
  State<PasswordSettingsScreen> createState() =>
      _PasswordSettingsScreenState();
}

class _PasswordSettingsScreenState extends State<PasswordSettingsScreen> {
  Map<String, bool> _toggles = {};
  bool _loading = true;
  bool _isDefault = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final toggles = <String, bool>{};
    for (final a in adminGatedActions) {
      // Never saved counts as ON — a new action is password-gated by default.
      toggles[a.id] = await state.db.getSetting(pwdToggleKey(a.id)) != '0';
    }
    await ensureAdminPassword(state);
    final isDefault = await adminPasswordIsDefault(state);
    if (!mounted) return;
    setState(() {
      _toggles = toggles;
      _isDefault = isDefault;
      _loading = false;
    });
  }

  Future<void> _setToggle(String id, bool value) async {
    final state = context.read<AppState>();
    await state.db.setSetting(pwdToggleKey(id), value ? '1' : '0');
    if (mounted) setState(() => _toggles[id] = value);
  }

  Future<void> _changePassword() async {
    final state = context.read<AppState>();
    final currentCtl = TextEditingController();
    final nextCtl = TextEditingController();
    final repeatCtl = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change admin password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentCtl,
                  obscureText: true,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Current password',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nextCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password (6+ characters)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: repeatCtl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Repeat new password',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Change')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      if (!await verifyAdminPassword(state, currentCtl.text)) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(
                content: Text('Current password is wrong.')));
        }
        return;
      }
      final next = nextCtl.text.trim();
      if (next != repeatCtl.text.trim()) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
                const SnackBar(content: Text('The new passwords do not match.')));
        }
        return;
      }
      try {
        await setAdminPassword(state, next);
      } on FormatException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Password changed.')));
      }
    } finally {
      currentCtl.dispose();
      nextCtl.dispose();
      repeatCtl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(title: const Text('Password Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SectionCard(
                  title: 'Ask Password for Delete / Release',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(
                          Icons.admin_panel_settings_outlined,
                          color: kGoldDark),
                      title: const Text('Ask password',
                          style: TextStyle(fontSize: 13.5)),
                      subtitle: const Text('Master switch — off skips every check',
                          style: TextStyle(fontSize: 11)),
                      value: state.adminConfirm,
                      onChanged: (v) => state.setAdminConfirm(v),
                    ),
                    const Divider(height: 16),
                    for (final a in adminGatedActions)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(a.label,
                            style: const TextStyle(fontSize: 13)),
                        value: _toggles[a.id] ?? true,
                        onChanged: (v) => _setToggle(a.id, v),
                      ),
                  ],
                ),
                SectionCard(
                  title: 'Admin password',
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_outline, color: kGoldDark),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _isDefault
                                ? 'Still using the default password — change it now.'
                                : 'Stored as a salted hash. It cannot be viewed.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _changePassword,
                      icon: const Icon(Icons.lock_reset_outlined, size: 18),
                      label: const Text('Change password'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Changing needs the current password first. Minimum 6 '
                      'characters; the default "admin" is refused.',
                      style:
                          TextStyle(fontSize: 11, color: mutedOf(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }
}
