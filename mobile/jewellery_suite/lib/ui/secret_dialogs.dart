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
