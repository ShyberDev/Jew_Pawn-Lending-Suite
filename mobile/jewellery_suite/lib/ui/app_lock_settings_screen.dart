import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/app_lock.dart';
import 'palette.dart';
import 'widgets.dart';

/// Settings → App lock (PIN). Off by default; the PIN is stored hashed and
/// never leaves the phone.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  bool _loading = true;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    final enabled = await AppLock.isEnabled(db);
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    final db = context.read<AppState>().db;
    if (value) {
      final pin = await _askNewPin(title: 'Set app-lock PIN');
      if (pin == null) return;
      await AppLock.setPin(db, pin);
    } else {
      final ok = await _askCurrentPin(title: 'Turn off app lock');
      if (!ok) return;
      await AppLock.disable(db);
    }
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(value
                ? 'App lock is on. It will ask for the PIN next time.'
                : 'App lock is off.')));
    }
  }

  Future<void> _changePin() async {
    final db = context.read<AppState>().db;
    if (!await _askCurrentPin(title: 'Change app-lock PIN')) return;
    if (!mounted) return;
    final pin = await _askNewPin(title: 'Set a new PIN');
    if (pin == null) return;
    await AppLock.setPin(db, pin);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('PIN changed.')));
    }
  }

  Future<bool> _askCurrentPin({required String title}) async {
    // Capture the database before the dialog's await; `context` must not be
    // read across the async gap.
    final db = context.read<AppState>().db;
    final ctl = TextEditingController();
    try {
      final typed = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: ctl,
            autofocus: true,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Current PIN',
              counterText: '',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctl.text),
                child: const Text('Continue')),
          ],
        ),
      );
      if (typed == null) return false;
      final ok = await AppLock.verify(db, typed);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('Wrong PIN.')));
      }
      return ok;
    } finally {
      ctl.dispose();
    }
  }

  Future<String?> _askNewPin({required String title}) async {
    final first = TextEditingController();
    final second = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: const InputDecoration(
                    labelText: 'New PIN (4–6 digits)',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: second,
                  obscureText: true,
                  maxLength: 6,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Repeat PIN',
                    counterText: '',
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
                child: const Text('Save')),
          ],
        ),
      );
      if (ok != true) return null;
      final a = first.text.trim();
      final b = second.text.trim();
      if (!AppLock.validPin(a)) {
        _toast('The PIN must be 4 to 6 digits.');
        return null;
      }
      if (a != b) {
        _toast('The PINs do not match.');
        return null;
      }
      return a;
    } finally {
      first.dispose();
      second.dispose();
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(title: const Text('App lock')),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SectionCard(
                  title: 'PIN lock',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.lock_outline,
                          color: kGoldDark),
                      title: const Text('Ask for a PIN when the app opens',
                          style: TextStyle(fontSize: 13.5)),
                      subtitle: const Text(
                          'Also locks after you switch to another app and back.',
                          style: TextStyle(fontSize: 11)),
                      value: _enabled,
                      onChanged: _toggle,
                    ),
                    if (_enabled) ...[
                      const Divider(height: 18),
                      OutlinedButton.icon(
                        onPressed: _changePin,
                        icon: const Icon(Icons.pin_outlined, size: 18),
                        label: const Text('Change PIN'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'The PIN is stored only as a salted hash. It never leaves '
                    'this phone and is not sent to a server. There is no PIN '
                    'recovery: if it is forgotten, the app data must be '
                    'cleared (make a backup first).',
                    style: TextStyle(
                        fontSize: 11.5, height: 1.45, color: mutedOf(context)),
                  ),
                ),
              ],
            ),
    );
  }
}
