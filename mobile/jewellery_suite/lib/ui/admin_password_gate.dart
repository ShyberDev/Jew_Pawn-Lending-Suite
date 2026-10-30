import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'admin_guard.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'palette.dart';

/// Startup gate that forces the shipped `admin` password to be replaced.
///
/// The v1.1.1 release defaulted to `admin` and kept it in plain text. Hashing
/// alone is not enough: every installed copy would share the same known
/// password. So the first launch after this build asks for a real password
/// before it shows the shop. Later launches go straight through.
class AdminPasswordGate extends StatefulWidget {
  const AdminPasswordGate({super.key});

  @override
  State<AdminPasswordGate> createState() => _AdminPasswordGateState();
}

class _AdminPasswordGateState extends State<AdminPasswordGate> {
  bool _checking = true;
  bool _needsChange = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final state = context.read<AppState>();
    final needsChange = await adminPasswordIsDefault(state);
    if (!mounted) return;
    setState(() {
      _needsChange = needsChange;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return Scaffold(
        backgroundColor: bgOf(context),
        body: const Center(child: CircularProgressIndicator(color: kGold)),
      );
    }
    if (_needsChange) {
      return AdminPasswordSetupScreen(
        onDone: () {
          if (mounted) setState(() => _needsChange = false);
        },
      );
    }
    return Consumer<AppState>(
      builder: (context, state, _) =>
          state.loggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}

/// First-run / recovery form: choose a non-default admin password.
///
/// There is deliberately no "skip": a known password is the defect this
/// screen exists to remove. The password is stored only as a salt + hash.
class AdminPasswordSetupScreen extends StatefulWidget {
  const AdminPasswordSetupScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<AdminPasswordSetupScreen> createState() =>
      _AdminPasswordSetupScreenState();
}

class _AdminPasswordSetupScreenState extends State<AdminPasswordSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await setAdminPassword(context.read<AppState>(), _next.text);
      if (!mounted) return;
      widget.onDone();
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('Could not save the password.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined,
                        size: 44, color: kGoldDark),
                    const SizedBox(height: 14),
                    Text('Set your admin password',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: inkOf(context))),
                    const SizedBox(height: 8),
                    Text(
                      'This password protects deletes, releases and sample-'
                      'data removal. The old default was known to everyone, so '
                      'choose a new one before the shop opens.\n\n'
                      'It is stored only as a salted hash — nobody, including '
                      'this app, can read it back. Keep a note somewhere safe.',
                      style: TextStyle(
                          fontSize: 13, height: 1.45, color: mutedOf(context)),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _next,
                      obscureText: _obscure,
                      autofocus: true,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        hintText: 'At least 6 characters',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show' : 'Hide',
                          icon: Icon(_obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.length < 6) return 'Use at least 6 characters.';
                        if (s.toLowerCase() == kDefaultAdminPassword) {
                          return 'Do not use the default password.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirm,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _save(),
                      decoration: const InputDecoration(
                        labelText: 'Repeat password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == _next.text ? null : 'The passwords do not match.',
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.lock_outline),
                        label: Text(_busy ? 'Saving…' : 'Save password'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
