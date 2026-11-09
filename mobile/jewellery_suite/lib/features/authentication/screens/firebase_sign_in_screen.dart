import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/palette.dart';
import '../../../ui/widgets.dart';
import '../cloud/cloud_sync.dart';
import '../cloud/firebase_auth_service.dart';
import '../cloud/firebase_bootstrap.dart';

/// The shop's cloud account: e-mail/password, Google and phone sign-in.
///
/// Kept separate from the local login so a phone that has never been online
/// still opens its own ledger. Once signed in here, the same account is used on
/// every device for Firestore (see docs/FIREBASE_SETUP.md).
class FirebaseSignInScreen extends StatefulWidget {
  const FirebaseSignInScreen({super.key});

  @override
  State<FirebaseSignInScreen> createState() => _FirebaseSignInScreenState();
}

enum _Method { email, google, phone }

class _FirebaseSignInScreenState extends State<FirebaseSignInScreen> {
  final _service = CloudAuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController(text: '+91 ');
  final _code = TextEditingController();

  StreamSubscription<User?>? _sub;
  User? _user;
  _Method _method = _Method.email;
  bool _create = false;
  bool _busy = false;
  bool _codeSent = false;
  String? _verificationId;
  String? _error;
  String? _info;

  bool get _ready => FirebaseBootstrap.ready;

  @override
  void initState() {
    super.initState();
    if (_ready) {
      _user = _service.user;
      _sub = _service.changes.listen((user) {
        if (mounted) setState(() => _user = user);
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    for (final c in [_email, _password, _phone, _code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = CloudAuthService.friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailAuth() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@')) {
      setState(() => _error = 'Enter the account e-mail address.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Use a password with at least 6 characters.');
      return;
    }
    await _guard(() async {
      if (_create) {
        await _service.createWithEmail(email, password);
      } else {
        await _service.signInWithEmail(email, password);
      }
    });
  }

  Future<void> _google() async {
    await _guard(() => _service.signInWithGoogle());
  }

  Future<void> _sendCode() async {
    final phone = _phone.text.replaceAll(RegExp(r'\s'), '');
    if (!phone.startsWith('+') || phone.length < 8) {
      setState(() => _error =
          'Enter the full number with country code, e.g. +919876543210.');
      return;
    }
    await _guard(() async {
      await _service.startPhoneSignIn(
        phoneNumber: phone,
        onCodeSent: (id, _) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _codeSent = true;
            _info = 'Code sent to $phone.';
          });
        },
        onError: (e) {
          if (mounted) setState(() => _error = e.message);
        },
        onSignedIn: (_) {
          if (mounted) setState(() => _info = 'Number verified.');
        },
      );
    });
  }

  Future<void> _verifyCode() async {
    final id = _verificationId;
    if (id == null) {
      setState(() => _error = 'Send the code first.');
      return;
    }
    if (_code.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    await _guard(() => _service.confirmPhoneCode(id, _code.text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgOf(context),
      appBar: AppBar(title: const Text('Cloud account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: _ready ? _body() : _notConfigured(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _notConfigured() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.cloud_off_outlined,
            size: 48, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        const Text('Firebase is not set up in this build yet.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Text(
          'The shop works fully offline without it. To turn cloud sign-in on, '
          'add android/app/google-services.json for the project '
          '"jewellery-suite--cloud" and rebuild — docs/FIREBASE_SETUP.md has '
          'the exact commands.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: mutedOf(context)),
        ),
        if (FirebaseBootstrap.error != null) ...[
          const SizedBox(height: 10),
          SelectableText(FirebaseBootstrap.error!,
              style: TextStyle(fontSize: 10.5, color: mutedOf(context))),
        ],
      ],
    );
  }

  Widget _body() {
    final user = _user;
    if (user != null) return _signedIn(user);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Sign in to keep every phone in step',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'This account is for cloud data only. The ledger on this phone still '
          'opens offline with its own PIN.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: mutedOf(context)),
        ),
        const SizedBox(height: 16),
        SegmentedButton<_Method>(
          segments: const [
            ButtonSegment(
                value: _Method.email,
                icon: Icon(Icons.mail_outline),
                label: Text('E-mail')),
            ButtonSegment(
                value: _Method.google,
                icon: Icon(Icons.account_circle_outlined),
                label: Text('Google')),
            ButtonSegment(
                value: _Method.phone,
                icon: Icon(Icons.sms_outlined),
                label: Text('Phone')),
          ],
          selected: {_method},
          onSelectionChanged: (s) => setState(() {
            _method = s.first;
            _error = null;
            _info = null;
          }),
        ),
        const SizedBox(height: 16),
        ...switch (_method) {
          _Method.email => _emailFields(),
          _Method.google => _googleFields(),
          _Method.phone => _phoneFields(),
        },
        if (_info != null) ...[
          const SizedBox(height: 10),
          Text(_info!,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              style: TextStyle(
                  fontSize: 12.5, color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  List<Widget> _emailFields() {
    return [
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: fieldDecoration('E-mail address'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: fieldDecoration('Password'),
        onSubmitted: (_) => _emailAuth(),
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _busy ? null : _emailAuth,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(_create ? Icons.person_add_alt_1 : Icons.login),
        label: Text(_busy
            ? 'Please wait…'
            : (_create ? 'Create account' : 'Sign in')),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _create = !_create;
                      _error = null;
                    }),
            child: Text(_create ? 'I already have one' : 'Create account'),
          ),
          if (!_create)
            TextButton(
              onPressed: _busy ? null : _resetPassword,
              child: const Text('Forgot password?'),
            ),
        ],
      ),
    ];
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Type the e-mail above, then tap again.');
      return;
    }
    await _guard(() async {
      await _service.sendPasswordReset(email);
      if (mounted) {
        setState(() => _info = 'Password reset link sent to $email.');
      }
    });
  }

  List<Widget> _googleFields() {
    return [
      Text(
        'Uses the Google account signed in on this phone. The shop data then '
        'belongs to that account.',
        style: TextStyle(fontSize: 12, color: mutedOf(context)),
      ),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _busy ? null : _google,
        icon: const Icon(Icons.account_circle),
        label: const Text('Continue with Google'),
      ),
    ];
  }

  List<Widget> _phoneFields() {
    return [
      TextField(
        controller: _phone,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
        decoration: fieldDecoration('Mobile number',
            hint: '+919876543210 (country code required)'),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _busy ? null : _sendCode,
        icon: const Icon(Icons.sms_outlined),
        label: Text(_codeSent ? 'Send a new code' : 'Send SMS code'),
      ),
      if (_codeSent) ...[
        const SizedBox(height: 14),
        TextField(
          controller: _code,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, letterSpacing: 6),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            counterText: '',
            labelText: '6-digit code',
            border: OutlineInputBorder(),
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _verifyCode,
          icon: const Icon(Icons.verified_user_outlined),
          label: const Text('Verify and sign in'),
        ),
      ],
      const SizedBox(height: 8),
      Text(
        'Phone sign-in needs this app\'s SHA-1 added in Firebase, and the '
        'number must be able to receive the SMS.',
        style: TextStyle(fontSize: 10.5, color: mutedOf(context)),
      ),
    ];
  }

  Widget _signedIn(User user) {
    final who = user.displayName?.trim();
    final lines = <String>[
      if (who != null && who.isNotEmpty) who,
      if (user.email != null) user.email!,
      if (user.phoneNumber != null) user.phoneNumber!,
      'ID ${user.uid}',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.cloud_done_outlined,
            size: 52, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 10),
        const Text('Signed in',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const SizedBox(height: 6),
        for (final line in lines)
          Text(line,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: mutedOf(context))),
        const SizedBox(height: 16),
        Text(
          'Every phone signed in to this account keeps the same stock ledger '
          'and worker records, live, through Firestore. The local ledger still '
          'works with no internet; the next sync catches up.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: mutedOf(context)),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<CloudSyncState>(
          valueListenable: CloudSync.instance.state,
          builder: (context, sync, _) => Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                          sync.live
                              ? Icons.cloud_sync
                              : Icons.cloud_queue_outlined,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      const Expanded(
                          child: Text('Live sync',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(sync.summary,
                      style: TextStyle(fontSize: 11.5, color: mutedOf(context))),
                  if (sync.error != null) ...[
                    const SizedBox(height: 4),
                    Text(sync.error!,
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: sync.busy
                        ? null
                        : () => CloudSync.instance.syncNow(),
                    icon: sync.busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync, size: 16),
                    label: Text(sync.busy ? 'Syncing…' : 'Sync now'),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () => _guard(() => _service.signOut()),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Sign out of the cloud account'),
        ),
      ],
    );
  }
}
