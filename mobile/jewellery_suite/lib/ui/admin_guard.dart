import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// Password-gated destructive actions.
///
/// This is an **accident guard for the shopkeeper, not security**: the string
/// ships inside the app, so anyone holding the APK can read it. Real
/// authentication is a separate decision; see the open items in the release
/// notes.
///
/// Everything password-related lives here, in one place:
/// - the registry of gated actions (add a line here and it automatically
///   appears as a toggle in Password Settings),
/// - the stored password (settings table, default `admin`, changeable),
/// - the single gate every screen calls.
const kDefaultAdminPassword = 'admin';

/// Every destructive action in the app, in one registry.
///
/// To gate a NEW action with a password: add one line here with a stable id
/// and a shopkeeper-readable label, then call [askPasswordIfEnabled] with that
/// id. It automatically appears as a toggle in Password Settings — no other
/// file needs to know about the settings UI.
const adminGatedActions = <({String id, String label})>[
  (id: 'khata_delete', label: 'Khata Delete'),
  (id: 'member_delete', label: 'Customer Delete'),
  (id: 'ledger_delete', label: 'Ledger Row Delete'),
  (id: 'move_to_loss', label: 'Move to Loss'),
  (id: 'pawn_delete', label: 'Pawn Delete'),
  (id: 'pawn_release', label: 'Pawn Release'),
  (id: 'history_clear', label: 'History Clear'),
  (id: 'sample_remove', label: 'Sample Data Remove'),
];

/// Settings key holding the current password (default [kDefaultAdminPassword]).
const kAdminPasswordKey = 'admin_password';

/// Settings key prefix holding one toggle per action id (`pwd_<id>` = '1').
String pwdToggleKey(String actionId) => 'pwd_$actionId';

/// The single gate every destructive action calls.
///
/// Returns true when the action may proceed: either its toggle (and the master
/// switch) is off, or the shopkeeper typed the current password.
/// Comparison is case-insensitive.
Future<bool> askPasswordIfEnabled(
  BuildContext context,
  AppState state, {
  required String actionId,
  required String action,
  String? detail,
  String confirmLabel = 'Delete',
}) async {
  final master = state.adminConfirm;
  final toggle = await state.db.getSetting(pwdToggleKey(actionId));
  // A toggle never saved counts as ON (password asked) — safe default.
  final enabled = master && toggle != '0';
  if (!enabled) return true;
  final current = await state.db.getSetting(kAdminPasswordKey) ??
      kDefaultAdminPassword;
  // The screen can be popped while the two reads above are in flight. This is a
  // destructive action, so it fails CLOSED: no screen, no password prompt, no
  // delete. Never grant an unlock to a context that no longer exists.
  if (!context.mounted) return false;
  return confirmAdmin(context,
      action: action,
      detail: detail,
      confirmLabel: confirmLabel,
      expected: current);
}

/// Asks for the password before a destructive [action].
///
/// Returns true only when the correct password is typed. [detail] names what
/// is being acted on (a customer, a khata) and appears in the question.
/// [confirmLabel] is the button the user presses to go ahead.
/// [expected] is the password to check against (default [kAdminPassword]).
Future<bool> confirmAdmin(
  BuildContext context, {
  required String action,
  String? detail,
  String confirmLabel = 'Delete',
  String expected = kDefaultAdminPassword,
}) async {
  final pw = TextEditingController();
  final subject = detail == null || detail.isEmpty ? '' : ' $detail';
  try {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Are you sure to $action$subject?'),
        content: TextField(
          controller: pw,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Type admin password',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, pw.text.trim().toLowerCase() == expected.toLowerCase()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return ok ?? false;
  } finally {
    pw.dispose();
  }
}

