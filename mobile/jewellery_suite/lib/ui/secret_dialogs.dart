import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/app_lock.dart';

/// Small shared dialogs for every PIN / password in the app, so the admin
/// password, the screen-lock PIN and the account password all look and behave
/// the same.

/// Asks for an existing PIN. Returns the typed digits, or null when cancelled.
Future<String?> askPinDialog(
  BuildContext context, {
  required String title,
  String label = 'Current PIN',
}) async {
  final ctl = TextEditingController();
  try {
    return await showDialog<String>(
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
          decoration: InputDecoration(
            labelText: label,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('Continue')),
        ],
      ),
    );
  } finally {
    ctl.dispose();
  }
}

/// Asks for an existing **password** (letters, digits and symbols).
///
/// [askPinDialog] is digits-only with a six-character cap — correct for the
/// MPIN, but it silently mangles a text password (`Admin@123` arrived as
/// `123`). The admin and pawn-move cards ask through this one instead.
Future<String?> askPasswordDialog(
  BuildContext context, {
  required String title,
  String label = 'Current password',
  String confirmLabel = 'Continue',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PasswordPrompt(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
    ),
  );
}

/// The prompt itself. The controller lives in a `State` so it is disposed with
/// the route instead of while the dialog is still animating out.
class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt({
    required this.title,
    required this.label,
    required this.confirmLabel,
  });

  final String title;
  final String label;
  final String confirmLabel;

  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _pw = TextEditingController();

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _pw,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _pw.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Asks for a new 4–6 digit PIN twice. Returns null on cancel or mismatch.
Future<String?> askNewPinDialog(
  BuildContext context, {
  required String title,
}) async {
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
      if (context.mounted) _toast(context, 'The PIN must be 4 to 6 digits.');
      return null;
    }
    if (a != b) {
      if (context.mounted) _toast(context, 'The PINs do not match.');
      return null;
    }
    return a;
  } finally {
    first.dispose();
    second.dispose();
  }
}

/// Asks for a new password twice. Returns null on cancel or mismatch.
Future<String?> askNewPasswordDialog(
  BuildContext context, {
  required String title,
  int minLength = 6,
  String label = 'New password',
}) async {
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
                decoration: InputDecoration(
                  labelText: '$label ($minLength+ characters)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: second,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Repeat password',
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
    if (a.length < minLength) {
      if (context.mounted) {
        _toast(context, 'Use at least $minLength characters.');
      }
      return null;
    }
    if (a != b) {
      if (context.mounted) _toast(context, 'The passwords do not match.');
      return null;
    }
    return a;
  } finally {
    first.dispose();
    second.dispose();
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
