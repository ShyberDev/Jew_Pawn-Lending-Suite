import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_bootstrap.dart';

/// A sign-in problem whose message is already written for the shopkeeper.
class CloudAuthError implements Exception {
  const CloudAuthError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cloud identity for the shop: e-mail/password, Google and phone sign-in.
///
/// This is separate from the phone's own local account (`LocalAccount`), which
/// keeps the ledger open offline. A Firebase account identifies the shop across
/// devices, so Firestore can hand the same data to every phone.
class CloudAuthService {
  CloudAuthService();

  /// The **Web** OAuth client ID from the Firebase project.
  ///
  /// `google_sign_in` needs it as `serverClientId` on Android; the Android
  /// client (package + SHA-1) is not enough on its own. Pass it at build time:
  /// `flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=1234-abc.apps.googleusercontent.com`
  static const webClientId =
      String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');

  FirebaseAuth get _auth => FirebaseAuth.instance;

  User? get user => _auth.currentUser;

  Stream<User?> get changes => _auth.authStateChanges();

  bool _googleInitialised = false;

  static void _requireFirebase() {
    if (!FirebaseBootstrap.ready) {
      throw const CloudAuthError(
          'Firebase is not configured in this build yet. Run the steps in '
          'docs/FIREBASE_SETUP.md, then rebuild.');
    }
  }

  // --------------------------------------------------------------- e-mail
  Future<UserCredential> signInWithEmail(String email, String password) async {
    _requireFirebase();
    return _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
  }

  Future<UserCredential> createWithEmail(String email, String password) async {
    _requireFirebase();
    return _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
  }

  Future<void> sendPasswordReset(String email) async {
    _requireFirebase();
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ---------------------------------------------------------------- Google
  Future<UserCredential?> signInWithGoogle() async {
    _requireFirebase();
    if (webClientId.isEmpty) {
      throw const CloudAuthError(
          'Google sign-in needs the Web client ID. Start the app with '
          '--dart-define=GOOGLE_WEB_CLIENT_ID=<web client id> '
          '(see docs/FIREBASE_SETUP.md).');
    }
    try {
      final google = GoogleSignIn.instance;
      if (!_googleInitialised) {
        await google.initialize(serverClientId: webClientId);
        _googleInitialised = true;
      }
      final account = await google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const CloudAuthError(
            'Google did not return an ID token. Check the Web client ID and '
            'the SHA-1 fingerprints registered in Firebase.');
      }
      return await _auth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        return null;
      }
      throw CloudAuthError(e.description ?? 'Google sign-in failed.');
    }
  }

  // ----------------------------------------------------------------- phone
  /// Sends the SMS code. [onCodeSent] receives the verification id, [onError]
  /// gets a readable message. Auto-retrieval may finish sign-in by itself,
  /// which is why [onSignedIn] exists.
  Future<void> startPhoneSignIn({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(CloudAuthError error) onError,
    void Function(UserCredential credential)? onSignedIn,
  }) async {
    _requireFirebase();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber.trim(),
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          final signed = await _auth.signInWithCredential(credential);
          onSignedIn?.call(signed);
        } catch (e) {
          onError(CloudAuthError(friendlyError(e)));
        }
      },
      verificationFailed: (e) => onError(CloudAuthError(friendlyError(e))),
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (verificationId) {},
    );
  }

  Future<UserCredential> confirmPhoneCode(
      String verificationId, String smsCode) async {
    _requireFirebase();
    return _auth.signInWithCredential(PhoneAuthProvider.credential(
        verificationId: verificationId, smsCode: smsCode.trim()));
  }

  Future<void> signOut() async {
    _requireFirebase();
    await _auth.signOut();
    if (_googleInitialised) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Signing out of the app must succeed even if Google cannot be reached.
      }
    }
  }

  /// Turns a Firebase / Google exception into one shop-readable sentence.
  static String friendlyError(Object error) {
    if (error is CloudAuthError) return error.message;
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That e-mail address is not valid.';
        case 'user-not-found':
          return 'No account uses that e-mail. Create the account first.';
        case 'wrong-password':
        case 'invalid-credential':
          return 'That e-mail and password do not match.';
        case 'email-already-in-use':
          return 'That e-mail already has an account. Sign in instead.';
        case 'weak-password':
          return 'Use a password with at least 6 characters.';
        case 'too-many-requests':
          return 'Too many attempts. Wait a few minutes and try again.';
        case 'invalid-verification-code':
          return 'That code is not correct. Check the SMS and retry.';
        case 'invalid-verification-id':
        case 'session-expired':
          return 'The code expired. Send a new one.';
        case 'invalid-phone-number':
          return 'Enter the number with its country code, e.g. +919876543210.';
        case 'operation-not-allowed':
          return 'This sign-in method is turned off in the Firebase console. '
              'Enable it under Authentication → Sign-in method.';
        case 'network-request-failed':
          return 'No internet connection. The ledger still works offline.';
        case 'requires-recent-login':
          return 'Sign in again before changing this account.';
        case 'quota-exceeded':
          return 'The SMS quota for today is used up. Try again tomorrow or '
              'sign in with e-mail.';
        default:
          return error.message ?? 'Sign-in failed (${error.code}).';
      }
    }
    if (error is GoogleSignInException) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return 'Google sign-in was cancelled.';
      }
      return error.description ?? 'Google sign-in failed.';
    }
    return 'Sign-in failed. ${error.toString()}';
  }
}
