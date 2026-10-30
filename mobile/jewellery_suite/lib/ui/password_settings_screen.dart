import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/app_lock.dart';
import '../util/otp_gateway.dart';
import 'admin_guard.dart';
import 'otp_flow.dart';
import 'palette.dart';
import 'secret_dialogs.dart';
import 'widgets.dart';

/// Home → System → Password Settings.
///
/// One place for **every** password:
///
/// * the login account (Gmail / mobile + password or one-time code),
/// * the admin password that guards deletes / releases,
/// * the screen lock PIN and the **Daily MPIN**.
///
/// Each one can be switched on or off, changed, and reset with a one-time code
/// when it is forgotten. The per-action switches are built from the
/// [adminGatedActions] registry, so a newly gated action appears here with no
/// extra UI work.
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
  String _lockMode = AppLock.off;
  final _gatewayCtl = TextEditingController();
  String _gatewayChannel = 'sms';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gatewayCtl.dispose();
    super.dispose();
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
    final mode = await AppLock.mode(state.db);
    final gatewayUrl = await OtpGateway.url(state.db);
    final channel = await OtpGateway.channel(state.db);
    if (!mounted) return;
    setState(() {
      _toggles = toggles;
      _isDefault = isDefault;
      _lockMode = mode;
      _gatewayCtl.text = gatewayUrl;
      _gatewayChannel = channel;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setToggle(String id, bool value) async {
    final state = context.read<AppState>();
    await state.db.setSetting(pwdToggleKey(id), value ? '1' : '0');
    if (mounted) setState(() => _toggles[id] = value);
  }

  // ------------------------------------------------------------- admin password
  Future<void> _changePassword() async {
    final state = context.read<AppState>();
    final pin = await askPinDialog(context,
        title: 'Change admin password', label: 'Current password');
    if (pin == null) return;
    if (!await verifyAdminPassword(state, pin)) {
      _toast('Current password is wrong.');
      return;
    }
    if (!mounted) return;
    final next = await askNewPasswordDialog(context,
        title: 'New admin password');
    if (next == null) return;
    try {
      await setAdminPassword(state, next);
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    }
    await _load();
    _toast('Admin password changed.');
  }

  Future<void> _forgotAdminPassword() async {
    final state = context.read<AppState>();
    final ok = await confirmWithOtp(
      context,
      state,
      purpose: 'admin_reset',
      title: 'Forgot admin password',
      subtitle: 'Reset the password used for deletes and releases.',
    );
    if (!ok || !mounted) return;
    final next = await askNewPasswordDialog(context,
        title: 'New admin password');
    if (next == null) return;
    try {
      await setAdminPassword(state, next);
    } on FormatException catch (e) {
      _toast(e.message);
      return;
    }
    await _load();
    _toast('Admin password reset.');
  }

  // ------------------------------------------------------------ login account
  Future<void> _registerAccount() async {
    final state = context.read<AppState>();
    final name = TextEditingController(text: state.userName);
    final id = TextEditingController();
    final pass = TextEditingController();
    try {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create the shop account'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: fieldDecoration('Your name')),
                const SizedBox(height: 8),
                TextField(
                    controller: id,
                    keyboardType: TextInputType.emailAddress,
                    decoration: fieldDecoration('Gmail / mobile *')),
                const SizedBox(height: 8),
                TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: fieldDecoration('Password (6+) *')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Create')),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      await state.createAccount(
          name: name.text, identifier: id.text, password: pass.text);
      _toast('Account created for ${state.accountIdentifier}.');
      setState(() {});
    } on FormatException catch (e) {
      _toast(e.message);
    } finally {
      name.dispose();
      id.dispose();
      pass.dispose();
    }
  }

  Future<void> _changeAccountPassword() async {
    final state = context.read<AppState>();
    final current = await askPinDialog(context,
        title: 'Change login password', label: 'Current password');
    if (current == null) return;
    if (!await state.loginPasswordMatches(current)) {
      _toast('Current password is wrong.');
      return;
    }
    if (!mounted) return;
    final next = await askNewPasswordDialog(context,
        title: 'New login password');
    if (next == null) return;
    await state.setAccountPassword(next);
    _toast('Login password changed.');
  }

  Future<void> _forgotAccountPassword() async {
    final state = context.read<AppState>();
    final ok = await confirmWithOtp(
      context,
      state,
      purpose: 'account_reset',
      title: 'Forgot login password',
      subtitle: 'Reset the password used to open the app.',
    );
    if (!ok || !mounted) return;
    final next = await askNewPasswordDialog(context,
        title: 'New login password');
    if (next == null) return;
    await state.setAccountPassword(next);
    _toast('Login password reset.');
  }

  // ------------------------------------------------------------- screen lock
  Future<void> _setLockMode(String mode) async {
    final state = context.read<AppState>();
    final db = state.db;
    if (mode == AppLock.off) {
      if (await AppLock.isEnabled(db)) {
        if (!mounted) return;
        final typed = await askPinDialog(context,
            title: 'Turn off the screen lock');
        if (typed == null) return;
        if (!await AppLock.verify(db, typed)) {
          _toast('Wrong PIN.');
          return;
        }
      }
      await AppLock.disable(db);
    } else if (!await AppLock.isEnabled(db)) {
      if (!mounted) return;
      final pin = await askNewPinDialog(context,
          title: mode == AppLock.daily ? 'Set the Daily MPIN' : 'Set the app PIN');
      if (pin == null) return;
      await AppLock.setPin(db, pin);
      await AppLock.setMode(db, mode);
    } else {
      await AppLock.setMode(db, mode);
    }
    final saved = await AppLock.mode(db);
    if (mounted) setState(() => _lockMode = saved);
    _toast(mode == AppLock.off
        ? 'Screen lock is off.'
        : mode == AppLock.daily
            ? 'Daily MPIN on — asked once a day.'
            : 'PIN lock on — asked every time.');
  }

  Future<void> _changePin() async {
    final state = context.read<AppState>();
    final db = state.db;
    final typed = await askPinDialog(context,
        title: 'Change PIN / MPIN', label: 'Current PIN');
    if (typed == null) return;
    if (!await AppLock.verify(db, typed)) {
      _toast('Wrong PIN.');
      return;
    }
    if (!mounted) return;
    final pin = await askNewPinDialog(context, title: 'Set a new PIN');
    if (pin == null) return;
    await AppLock.setPin(db, pin);
    _toast('PIN changed.');
  }

  Future<void> _forgotPin() async {
    final state = context.read<AppState>();
    final db = state.db;
    final currentMode = await AppLock.mode(db);
    if (!mounted) return;
    final ok = await confirmWithOtp(
      context,
      state,
      purpose: 'pin_reset',
      title: 'Forgot PIN / MPIN',
      subtitle: 'Reset the screen lock with a one-time code.',
    );
    if (!ok) return;
    if (!mounted) return;
    final pin = await askNewPinDialog(context, title: 'Set a new PIN');
    if (pin == null || !mounted) return;
    await AppLock.setPin(db, pin);
    await AppLock.setMode(
        db, currentMode == AppLock.off ? AppLock.always : currentMode);
    final saved = await AppLock.mode(db);
    if (mounted) setState(() => _lockMode = saved);
    _toast('PIN reset.');
  }

  Future<void> _saveGateway() async {
    final state = context.read<AppState>();
    final url = _gatewayCtl.text.trim();
    if (url.isNotEmpty && !url.startsWith('http')) {
      _toast('The gateway URL must start with http or https.');
      return;
    }
    if (url.isEmpty) {
      await OtpGateway.clear(state.db);
      _toast('One-time codes will be shown on this phone.');
      return;
    }
    await OtpGateway.configure(state.db, url: url, channel: _gatewayChannel);
    _toast('Codes will be sent by ${_gatewayChannel == 'email' ? 'e-mail' : 'SMS'}.');
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
                _accountCard(state),
                _lockCard(state),
                _deleteReleaseCard(state),
                _adminCard(state),
                _otpDeliveryCard(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _otpDeliveryCard() {
    return SectionCard(
      title: 'One-time code delivery (SMS / Gmail)',
      children: [
        Text(
          'Forgot-password codes go to the account email / mobile. Add your '
          'SMS or e-mail gateway URL here to send them for real; without it the '
          'code is shown on this phone so you are never locked out.',
          style: TextStyle(fontSize: 12, color: mutedOf(context)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _gatewayCtl,
          keyboardType: TextInputType.url,
          decoration: fieldDecoration('Gateway URL',
              hint: 'https://your-sms-or-mail-gateway/send'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final (value, label) in const [
              ('sms', 'SMS'),
              ('email', 'E-mail'),
            ]) ...[
              ChoiceChip(
                label: Text(label),
                selected: _gatewayChannel == value,
                selectedColor: kGold.withValues(alpha: .3),
                onSelected: (_) => setState(() => _gatewayChannel = value),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _saveGateway,
              icon: const Icon(Icons.save_outlined, size: 17),
              label: const Text('Save gateway'),
            ),
            TextButton.icon(
              onPressed: () async {
                await OtpGateway.clear(context.read<AppState>().db);
                _gatewayCtl.clear();
                _toast('Gateway removed — codes are shown on this phone.');
              },
              icon: const Icon(Icons.link_off, size: 17),
              label: const Text('Remove gateway'),
            ),
          ],
        ),
        Text(
          'The gateway receives POST JSON: to, channel, purpose, code, message. '
          'Any 2xx reply counts as sent.',
          style: TextStyle(fontSize: 10.5, color: mutedOf(context)),
        ),
      ],
    );
  }

  Widget _accountCard(AppState state) {
    return SectionCard(
      title: 'Account & login',
      children: [
        if (state.hasAccount)
          Row(
            children: [
              const Icon(Icons.account_circle_outlined, color: kGoldDark),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(state.accountIdentifier,
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text(
                      'Stays signed in until you log out.',
                      style: TextStyle(fontSize: 11, color: mutedOf(context)),
                    ),
                  ],
                ),
              ),
            ],
          )
        else ...[
          Text(
            'Create an account with a Gmail address or mobile number. It is '
            'what the "Forgot password" codes are sent to.',
            style: TextStyle(fontSize: 12, color: mutedOf(context)),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _registerAccount,
            icon: const Icon(Icons.person_add_alt_1, size: 18),
            label: const Text('Create account'),
          ),
        ],
        const Divider(height: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Sign in with password',
              style: TextStyle(fontSize: 13)),
          value: state.passwordLoginEnabled,
          onChanged: (v) => state.setLoginMethods(password: v),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Sign in with one-time code',
              style: TextStyle(fontSize: 13)),
          subtitle: const Text('Gmail / mobile OTP',
              style: TextStyle(fontSize: 11)),
          value: state.otpLoginEnabled,
          onChanged: (v) => state.setLoginMethods(otp: v),
        ),
        if (state.hasAccount)
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _changeAccountPassword,
                icon: const Icon(Icons.password, size: 17),
                label: const Text('Change password'),
              ),
              TextButton.icon(
                onPressed: _forgotAccountPassword,
                icon: const Icon(Icons.help_outline, size: 17),
                label: const Text('Forgot password?'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _lockCard(AppState state) {
    return SectionCard(
      title: 'Biometric & screen lock',
      children: [
        Text(
          'Ask for a 4–6 digit PIN when the app opens. "Daily MPIN" asks once '
          'per day; "Every time" also locks when you return from another app.',
          style: TextStyle(fontSize: 12, color: mutedOf(context)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (label, value, icon) in <(String, String, IconData)>[
              ('Off', AppLock.off, Icons.lock_open_outlined),
              ('Every time', AppLock.always, Icons.lock_outline),
              ('Daily MPIN', AppLock.daily, Icons.today_outlined),
            ])
              ChoiceChip(
                key: ValueKey('lock-mode-$value'),
                avatar: Icon(icon, size: 15,
                    color: _lockMode == value ? kGoldDark : mutedOf(context)),
                label: Text(label),
                selected: _lockMode == value,
                selectedColor: kGold.withValues(alpha: .3),
                onSelected: (_) => _setLockMode(value),
              ),
          ],
        ),
        if (_lockMode != AppLock.off) ...[
          const Divider(height: 20),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _changePin,
                icon: const Icon(Icons.pin_outlined, size: 17),
                label: const Text('Change PIN'),
              ),
              TextButton.icon(
                onPressed: _forgotPin,
                icon: const Icon(Icons.help_outline, size: 17),
                label: const Text('Forgot PIN?'),
              ),
            ],
          ),
          Text(
            'The PIN is stored only as a salted hash. Resetting it needs the '
            'one-time code from your account.',
            style: TextStyle(fontSize: 11, color: mutedOf(context)),
          ),
        ],
      ],
    );
  }

  Widget _deleteReleaseCard(AppState state) {
    return SectionCard(
      title: 'Ask Password for Delete / Release',
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.admin_panel_settings_outlined,
              color: kGoldDark),
          title: const Text('Ask password', style: TextStyle(fontSize: 13.5)),
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
            title: Text(a.label, style: const TextStyle(fontSize: 13)),
            value: _toggles[a.id] ?? true,
            onChanged: (v) => _setToggle(a.id, v),
          ),
      ],
    );
  }

  Widget _adminCard(AppState state) {
    return SectionCard(
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
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _changePassword,
              icon: const Icon(Icons.lock_reset_outlined, size: 18),
              label: const Text('Change password'),
            ),
            TextButton.icon(
              onPressed: _forgotAdminPassword,
              icon: const Icon(Icons.help_outline, size: 17),
              label: const Text('Forgot password?'),
            ),
          ],
        ),
        Text(
          'Changing needs the current password; a forgotten one is reset with '
          'a one-time code. Minimum 6 characters; the default "admin" is refused.',
          style: TextStyle(fontSize: 11, color: mutedOf(context)),
        ),
      ],
    );
  }
}
