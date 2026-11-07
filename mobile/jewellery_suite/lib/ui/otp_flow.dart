import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../util/otp_gateway.dart';
import 'admin_guard.dart';
import 'palette.dart';
import 'secret_dialogs.dart';

/// One-time-code confirmation shared by every "Forgot password" entry point.
///
/// The app is offline-first and has no SMS / e-mail gateway of its own, so the
/// code is generated on this phone and shown in the dialog, clearly labelled
/// as an **offline code**. It is still a real one-time code: hashed at rest,
/// valid for 10 minutes, and blocked after five wrong attempts. If the shop
/// later connects an SMS or e-mail gateway, only [LocalAccount.issueOtp]
/// changes — this flow stays the same.
Future<bool> confirmWithOtp(
  BuildContext context,
  AppState state, {
  required String purpose,
  required String title,
  String? subtitle,
}) async {
  if (!state.hasAccount) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No account registered'),
        content: const Text(
          'A one-time code is sent to your account email / mobile. Create the '
          'account first in Password Settings → Account & login, then every '
          'password can be reset here.',
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
    return false;
  }

  final identifier = state.accountIdentifier;

  // Step 1 — confirm where the code should go.
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      // The keypad covers half a phone screen; without this the Send code
      // button scrolls out of reach and the reset looks broken.
      scrollable: true,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) ...[
            Text(subtitle, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
          ],
          Text('Send a 6-digit code to',
              style: TextStyle(fontSize: 12, color: mutedOf(ctx))),
          const SizedBox(height: 2),
          Text(identifier, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send code')),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return false;

  // #085: the gateway POST waits up to 12 s before giving up. On the v1.4.20
  // phone pass, tapping **Send code** simply closed the dialog — no code box,
  // no error, nothing — so the reset looked dead. Keep a progress dialog on
  // screen for the whole exchange, and never end it without a code to type.
  final nav = Navigator.of(context);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _SendingCodeDialog(),
  ));

  String code;
  var delivered = false;
  try {
    code = await state.issueOtp(purpose);
    // Try the configured SMS / e-mail gateway first. Only when nothing is
    // configured (or the send fails) is the code shown on the phone.
    delivered = await OtpGateway.send(
        db: state.db, to: identifier, code: code, purpose: purpose);
  } catch (_) {
    // A failed send must still leave the shop a way in: issue a fresh code and
    // show it on the phone instead of dropping the whole reset.
    code = await state.issueOtp(purpose);
    delivered = false;
  } finally {
    if (context.mounted) nav.pop();
  }
  if (!context.mounted) return false;

  final entered = await askOtpCodeDialog(context,
      code: code, identifier: identifier, delivered: delivered);
  if (entered == null || !context.mounted) return false;
  final ok = await state.verifyOtp(purpose, entered);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
          content: Text('The code is wrong or has expired. Try again.')));
  }
  return ok;
}

/// Shown while the code is issued and handed to the SMS / e-mail gateway.
class _SendingCodeDialog extends StatelessWidget {
  const _SendingCodeDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: kGold),
          ),
          SizedBox(width: 14),
          Flexible(child: Text('Sending the code…')),
        ],
      ),
    );
  }
}

/// Confirms a lock-screen reset when the shop is locked out.
///
/// The lock screen cannot reach Password Settings, so a phone with no Gmail /
/// mobile account had nowhere to get a one-time code from: "Forgot PIN?" ended
/// in a dialog telling the shop to create an account they could not reach. With
/// no account the admin password is asked instead — the same secret the delete
/// and release prompts already use — so a locked phone is never a dead end.
Future<bool> confirmLockReset(
  BuildContext context,
  AppState state, {
  required String purpose,
  required String title,
  String? subtitle,
}) async {
  if (state.hasAccount) {
    return confirmWithOtp(context, state,
        purpose: purpose, title: title, subtitle: subtitle);
  }
  final typed =
      await askPasswordDialog(context, title: title, label: 'Admin password');
  if (typed == null || !context.mounted) return false;
  if (!await verifyAdminPassword(state, typed)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            const SnackBar(content: Text('That admin password is wrong.')));
    }
    return false;
  }
  return true;
}

/// Shows the generated code (offline delivery) and asks the user to type it.
/// Public so the login screen's OTP sign-in uses the same dialog.
Future<String?> askOtpCodeDialog(
  BuildContext context, {
  required String code,
  required String identifier,
  bool delivered = false,
}) async {
  return showDialog<String>(
    context: context,
    builder: (_) => _OtpCodePrompt(
      code: code,
      identifier: identifier,
      delivered: delivered,
    ),
  );
}

/// The prompt itself. The controller lives in a `State` so it is disposed with
/// the route, not while the dialog is still animating out: disposing it in a
/// `finally` threw *“A TextEditingController was used after being disposed”* on
/// every close (#085).
class _OtpCodePrompt extends StatefulWidget {
  const _OtpCodePrompt({
    required this.code,
    required this.identifier,
    required this.delivered,
  });

  final String code;
  final String identifier;
  final bool delivered;

  @override
  State<_OtpCodePrompt> createState() => _OtpCodePromptState();
}

class _OtpCodePromptState extends State<_OtpCodePrompt> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return AlertDialog(
      // Six digits plus the code box overflows a phone once the keypad is up.
      scrollable: true,
      title: const Text('Enter the 6-digit code'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kGold.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kGold.withValues(alpha: .5)),
            ),
            child: widget.delivered
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Code sent',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'A 6-digit code was sent to ${widget.identifier}. '
                        'It is valid '
                        'for 10 minutes.',
                        style: TextStyle(fontSize: 10.5, color: mutedOf(ctx)),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Offline code (valid 10 minutes)',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      SelectableText(widget.code,
                          style: const TextStyle(
                              fontSize: 26,
                              letterSpacing: 6,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        'No SMS / e-mail gateway is configured (or the send '
                        'failed), so the code appears here instead of going '
                        'to ${widget.identifier}.',
                        style: TextStyle(fontSize: 10.5, color: mutedOf(ctx)),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctl,
            autofocus: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, letterSpacing: 6),
            decoration: const InputDecoration(
              counterText: '',
              labelText: 'Code',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, _ctl.text),
            child: const Text('Verify')),
      ],
    );
  }
}
