import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/features/authentication/cloud/firebase_auth_service.dart';

/// The shopkeeper sees `friendlyError`, never a raw Firebase code, so every
/// mapping that a real sign-in can hit is pinned here.
void main() {
  test('common sign-in failures read as sentences', () {
    String map(String code) =>
        CloudAuthService.friendlyError(FirebaseAuthException(code: code));

    expect(map('wrong-password'), contains('do not match'));
    expect(map('invalid-credential'), contains('do not match'));
    expect(map('user-not-found'), contains('Create the account first'));
    expect(map('email-already-in-use'), contains('already has an account'));
    expect(map('weak-password'), contains('6 characters'));
    expect(map('invalid-verification-code'), contains('not correct'));
    expect(map('invalid-phone-number'), contains('+91'));
    expect(map('operation-not-allowed'), contains('Firebase console'));
    expect(map('network-request-failed'), contains('offline'));
    expect(map('too-many-requests'), contains('Wait'));
  });

  test('an unknown code still names the failure', () {
    final text = CloudAuthService.friendlyError(
        FirebaseAuthException(code: 'something-new', message: 'Server said no'));
    expect(text, contains('Server said no'));
  });

  test('our own messages pass through unchanged', () {
    expect(CloudAuthService.friendlyError(const CloudAuthError('Set the ID')),
        'Set the ID');
  });

  test('Firebase not being configured is explained, not thrown as a code', () {
    final text = CloudAuthService.friendlyError(
        const CloudAuthError('Firebase is not configured in this build yet.'));
    expect(text, contains('not configured'));
  });
}
