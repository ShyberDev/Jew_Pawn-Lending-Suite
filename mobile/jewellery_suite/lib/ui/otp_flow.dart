import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../util/otp_gateway.dart';
import 'palette.dart';

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
          Text(identifier,
              style: const TextStyle(fontWeight: FontWeight.w700)),
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
  if (proceed != true) return false;

  final code = await state.issueOtp(purpose);
  // Try the configured SMS / e-mail gateway first. Only when nothing is
  // configured (or the send fails) is the code shown on the phone.
  final delivered = await OtpGateway.send(
      db: state.db, to: identifier, code: code, purpose: purpose);
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

/// Shows the generated code (offline delivery) and asks the user to type it.
/// Public so the login screen's OTP sign-in uses the same dialog.
Future<String?> askOtpCodeDialog(
  BuildContext context, {
  required String code,
  required String identifier,
  bool delivered = false,
}) async {
  final ctl = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
              child: delivered
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Code sent',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'A 6-digit code was sent to $identifier. It is valid '
                          'for 10 minutes.',
                          style:
                              TextStyle(fontSize: 10.5, color: mutedOf(ctx)),
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
                        SelectableText(code,
                            style: const TextStyle(
                                fontSize: 26,
                                letterSpacing: 6,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          'No SMS / e-mail gateway is configured (or the send '
                          'failed), so the code appears here instead of going '
                          'to $identifier.',
                          style: TextStyle(fontSize: 10.5, color: mutedOf(ctx)),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
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
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('Verify')),
        ],
      ),
    );
  } finally {
    ctl.dispose();
  }
}
