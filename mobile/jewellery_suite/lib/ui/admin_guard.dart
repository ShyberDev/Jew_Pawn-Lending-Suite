import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../util/app_lock.dart';
import '../util/secret_hash.dart';

/// Password-gated destructive actions.
///
/// This is an **accident guard for the shopkeeper, not remote authentication**:
/// the hash ships on the device, so a determined attacker with the unlocked
/// phone can still clear app data. What it must never do is store the password
/// itself. v1.1.1 kept `admin` in plain text in `settings`; this file now
/// stores only a random salt + stretched hash.
///
/// Everything password-related lives here, in one place:
/// - the registry of gated actions (add a line here and it automatically
///   appears as a toggle in Password Settings),
/// - the stored hash/salt (settings table),
/// - the single gate every screen calls.
///
/// The old plain-text key is read once, migrated, then erased. `admin` remains
/// only as the legacy default so a first launch can detect it and force a
/// change; it is never accepted once a real password is set.
const kDefaultAdminPassword = 'admin';

const kAdminPasswordHashKey = 'admin_password_hash';
const kAdminPasswordSaltKey = 'admin_password_salt';
const kLegacyAdminPasswordKey = 'admin_password';

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
  (id: 'backup_restore', label: 'Backup Restore'),
];

/// Settings key prefix holding one toggle per action id (`pwd_<id>` = '1').
String pwdToggleKey(String actionId) => 'pwd_$actionId';

/// Makes sure a hashed password exists. A database upgraded from v1.1.1 may
/// still hold the plain-text key; it is read exactly once, hashed, and then
/// removed. Never returns the password itself.
Future<void> ensureAdminPassword(AppState state) async {
  final db = state.db;
  final existingHash = await db.getSetting(kAdminPasswordHashKey);
  final existingSalt = await db.getSetting(kAdminPasswordSaltKey);
  if (existingHash != null &&
      existingHash.isNotEmpty &&
      existingSalt != null &&
      existingSalt.isNotEmpty) {
    // Clean up a legacy row even if a previous run already wrote the hash.
    if (await db.getSetting(kLegacyAdminPasswordKey) != null) {
      await db.setSetting(kLegacyAdminPasswordKey, null);
    }
    return;
  }
  final legacy = await db.getSetting(kLegacyAdminPasswordKey);
  final seed = (legacy == null || legacy.trim().isEmpty)
      ? kDefaultAdminPassword
      : legacy;
  final salt = randomSalt();
  await db.setSetting(kAdminPasswordSaltKey, salt);
  await db.setSetting(kAdminPasswordHashKey, hashSecret(seed, salt));
  await db.setSetting(kLegacyAdminPasswordKey, null);
}

/// True while the password is still the shipped default (`admin`). The startup
/// gate uses this to force a change before the shop can be used.
Future<bool> adminPasswordIsDefault(AppState state) async {
  await ensureAdminPassword(state);
  return verifyAdminPassword(state, kDefaultAdminPassword);
}

/// Checks [input] against the stored salted hash.
Future<bool> verifyAdminPassword(AppState state, String input) async {
  await ensureAdminPassword(state);
  final hash = await state.db.getSetting(kAdminPasswordHashKey) ?? '';
  final salt = await state.db.getSetting(kAdminPasswordSaltKey) ?? '';
  if (hash.isEmpty || salt.isEmpty) return false;
  return constantTimeEquals(hashSecret(input, salt), hash);
}

/// Replaces the password with a fresh salt + hash. Rejects the shipped default
/// and anything shorter than six characters, so the "force change" gate cannot
/// immediately undo itself.
Future<void> setAdminPassword(AppState state, String next) async {
  final trimmed = next.trim();
  if (trimmed.length < 6) {
    throw const FormatException('Use at least 6 characters.');
  }
  if (trimmed.toLowerCase() == kDefaultAdminPassword) {
    throw const FormatException('Do not use the default password.');
  }
  final salt = randomSalt();
  await state.db.setSetting(kAdminPasswordSaltKey, salt);
  await state.db.setSetting(kAdminPasswordHashKey, hashSecret(trimmed, salt));
  await state.db.setSetting(kLegacyAdminPasswordKey, null);
}

/// The single gate every destructive action calls.
///
/// Returns true when the action may proceed: either its toggle (and the master
/// switch) is off, or the shopkeeper typed the current secret.
///
/// **Which secret:** the everyday **MPIN** (the screen-lock PIN in Password
/// Settings) is what the shop floor types, so it is checked first. The long
/// admin password is only asked when no MPIN is set — otherwise a shop that
/// never configured a PIN would have no way past the delete / release prompt.
/// A 4–6 digit MPIN must never be accepted as an admin password or the other
/// way round: each is verified against its own salted hash.
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
  // The MPIN is only usable once it has been set AND the screen lock is on.
  final useMpin = await AppLock.isEnabled(state.db);
  // The screen can be popped while the reads above are in flight. This is a
  // destructive action, so it fails CLOSED: no screen, no prompt, no delete.
  if (!context.mounted) return false;
  return confirmAdmin(
    context,
    action: action,
    detail: detail,
    confirmLabel: confirmLabel,
    labelText: useMpin ? 'Type MPIN' : 'Type admin password',
    keyboardType: useMpin ? TextInputType.number : TextInputType.text,
    verify: (typed) => useMpin
        ? AppLock.verify(state.db, typed)
        : verifyAdminPassword(state, typed),
  );
}

/// Asks for the password before a destructive [action].
///
/// Returns true only when [verify] accepts what was typed. [detail] names what
/// is being acted on (a customer, a khata) and appears in the question.
/// [confirmLabel] is the button the user presses to go ahead.
Future<bool> confirmAdmin(
  BuildContext context, {
  required String action,
  String? detail,
  String confirmLabel = 'Delete',
  String labelText = 'Type admin password',
  TextInputType? keyboardType,
  required Future<bool> Function(String typed) verify,
}) async {
  final pw = TextEditingController();
  final subject = detail == null || detail.isEmpty ? '' : ' $detail';
  try {
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Are you sure to $action$subject?'),
        content: TextField(
          controller: pw,
          obscureText: true,
          autofocus: true,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            labelText: labelText,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, pw.text),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (typed == null) return false;
    return await verify(typed);
  } finally {
    pw.dispose();
  }
}
