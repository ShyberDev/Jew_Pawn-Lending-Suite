import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../util/otp_gateway.dart';
import 'otp_flow.dart';
import 'palette.dart';
import 'secret_dialogs.dart';
import 'widgets.dart';

/// Sign in / create the shop's account.
///
/// The account is a Gmail address or a 10-digit mobile number plus a password,
/// stored on this phone. Signing in once keeps the shop open across restarts
/// until **Logout** — no daily login. Each method can be switched off in
/// Password Settings, and every password has a "Forgot?" path that resets it
/// with a one-time code.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _name = TextEditingController();
  final _otp = TextEditingController();

  // Optional LAN / shop server (sync). Unrelated to the local account.
  late final TextEditingController _url;
  final _serverUser = TextEditingController();
  final _serverPass = TextEditingController();
  bool _serverOpen = false;

  bool _createMode = false;
  bool _useOtp = false;
  bool _otpSent = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _identifier.text = state.accountIdentifier;
    _createMode = !state.hasAccount;
    _useOtp = !state.passwordLoginEnabled && state.otpLoginEnabled;
    _url = TextEditingController(
        text: state.serverUrl.isEmpty
            ? 'http://192.168.1.10:8000'
            : state.serverUrl);
  }

  @override
  void dispose() {
    for (final c in [
      _identifier,
      _password,
      _confirm,
      _name,
      _otp,
      _url,
      _serverUser,
      _serverPass,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function(AppState) action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(context.read<AppState>());
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    await _run((state) => state.createAccount(
          name: _name.text,
          identifier: _identifier.text,
          password: _password.text,
        ));
  }

  Future<void> _signInPassword() async {
    if (!_formKey.currentState!.validate()) return;
    await _run((state) =>
        state.signInWithPassword(_identifier.text, _password.text));
  }

  Future<void> _sendOtp() async {
    if (_identifier.text.trim().isEmpty) {
      setState(() => _error = 'Enter the Gmail address / mobile number.');
      return;
    }
    await _run((state) async {
      final to = _identifier.text.trim();
      final code = await state.issueOtp('login');
      final delivered = await OtpGateway.send(
          db: state.db, to: to, code: code, purpose: 'login');
      if (!mounted) return;
      final entered = await askOtpCodeDialog(context,
          code: code, identifier: to, delivered: delivered);
      if (entered == null) return;
      _otp.text = entered;
      if (mounted) setState(() => _otpSent = true);
    });
  }

  Future<void> _signInOtp() async {
    if (_otp.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    await _run((state) =>
        state.signInWithOtp(_identifier.text, _otp.text));
  }

  Future<void> _forgotPassword() async {
    final state = context.read<AppState>();
    final ok = await confirmWithOtp(
      context,
      state,
      purpose: 'account_reset',
      title: 'Forgot login password',
      subtitle: 'Reset the password for your account.',
    );
    if (!ok || !mounted) return;
    final next = await askNewPasswordDialog(context, title: 'New login password');
    if (next == null) return;
    await state.setAccountPassword(next);
    _toast('Login password changed. Sign in with the new one.');
    if (mounted) setState(() => _useOtp = false);
  }

  Future<void> _serverLogin() async {
    if (_url.text.trim().isEmpty) {
      setState(() => _error = 'Enter the server URL.');
      return;
    }
    await _run((state) =>
        state.login(_url.text.trim(), _serverUser.text.trim(), _serverPass.text));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canSignIn = state.hasAccount;
    final showCreate = _createMode || !canSignIn;

    return Scaffold(
      backgroundColor: bgOf(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.diamond_outlined,
                        size: 60, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 6),
                    Text('Jewellery Suite',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 4),
                    Text(
                      showCreate
                          ? 'Create your shop account once. After that the app stays signed in until you log out.'
                          : 'Welcome back. Sign in once — the shop stays open until Logout.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: mutedOf(context)),
                    ),
                    const SizedBox(height: 18),
                    if (canSignIn && showCreate)
                      _switchRow('Sign in instead', () {
                        setState(() => _createMode = false);
                      }),
                    if (!canSignIn && !showCreate)
                      _switchRow('Create an account', () {
                        setState(() => _createMode = true);
                      }),
                    if (showCreate) ..._createFields() else ..._signInFields(state),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12.5)),
                    ],
                    const SizedBox(height: 14),
                    _serverSection(),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => context.read<AppState>().continueOffline(),
                      icon: const Icon(Icons.phonelink_off_outlined, size: 18),
                      label: const Text('Use without a server'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The ledger works fully offline. Choose this when no shop '
                      'server is set up — you can still create the account above '
                      'for MPIN and password recovery.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10.5, color: mutedOf(context)),
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

  Widget _switchRow(String label, VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(onPressed: onTap, child: Text(label)),
    );
  }

  List<Widget> _createFields() {
    return [
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: fieldDecoration('Your name'),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Required' : null,
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: _identifier,
        keyboardType: TextInputType.emailAddress,
        decoration: fieldDecoration('Gmail or mobile number *',
            hint: 'you@gmail.com  /  9876543210'),
        validator: (v) => (v == null || !_validId(v))
            ? 'Enter a Gmail address or 10-digit mobile'
            : null,
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: _password,
        obscureText: true,
        decoration: fieldDecoration('Password (6+ characters) *'),
        validator: (v) =>
            (v == null || v.trim().length < 6) ? 'Use 6+ characters' : null,
      ),
      const SizedBox(height: 10),
      TextFormField(
        controller: _confirm,
        obscureText: true,
        decoration: fieldDecoration('Repeat password *'),
        validator: (v) => v != _password.text ? 'Passwords do not match' : null,
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy ? null : _create,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.person_add_alt_1),
        label: Text(_busy ? 'Creating…' : 'Create account'),
      ),
    ];
  }

  bool _validId(String value) {
    final v = value.trim();
    if (RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$').hasMatch(v)) return true;
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10 ||
        (digits.length == 12 && digits.startsWith('91'));
  }

  List<Widget> _signInFields(AppState state) {
    return [
      TextFormField(
        controller: _identifier,
        keyboardType: TextInputType.emailAddress,
        decoration: fieldDecoration('Gmail or mobile number'),
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      ),
      const SizedBox(height: 10),
      if (!_useOtp) ...[
        TextFormField(
          controller: _password,
          obscureText: true,
          decoration: fieldDecoration('Password'),
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          onFieldSubmitted: (_) => _signInPassword(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _busy ? null : _forgotPassword,
            child: const Text('Forgot password?',
                style: TextStyle(fontSize: 12.5)),
          ),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _signInPassword,
          icon: const Icon(Icons.login),
          label: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
      ] else ...[
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _otp,
                maxLength: 6,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, letterSpacing: 5),
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: '6-digit code',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _sendOtp,
              child: Text(_otpSent ? 'Resend' : 'Send code'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        FilledButton.icon(
          onPressed: _busy ? null : _signInOtp,
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Sign in with code'),
        ),
      ],
      if (state.passwordLoginEnabled && state.otpLoginEnabled)
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _useOtp = !_useOtp;
                      _error = null;
                    }),
            child: Text(_useOtp
                ? 'Use password instead'
                : 'Sign in with a one-time code'),
          ),
        )
      else if (!state.otpLoginEnabled)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('One-time code sign-in is turned off in Password Settings.',
              style: TextStyle(fontSize: 11, color: mutedOf(context))),
        ),
    ];
  }

  Widget _serverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextButton.icon(
          onPressed: () => setState(() => _serverOpen = !_serverOpen),
          icon: Icon(
              _serverOpen ? Icons.expand_less : Icons.expand_more,
              size: 18),
          label: const Text('Connect to the shop server (optional)'),
        ),
        if (_serverOpen) ...[
          TextFormField(
            controller: _url,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://192.168.1.10:8000',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _serverUser,
            decoration: fieldDecoration('Server username'),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _serverPass,
            obscureText: true,
            decoration: fieldDecoration('Server password'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _serverLogin,
            icon: const Icon(Icons.cloud_outlined, size: 18),
            label: const Text('Connect & sign in'),
          ),
          const SizedBox(height: 4),
          Text(
            'Sync only. The shop account above still works without it.',
            style: TextStyle(fontSize: 10.5, color: mutedOf(context)),
          ),
        ],
      ],
    );
  }
}
