import 'package:flutter_test/flutter_test.dart';
import 'package:jewellery_suite/util/biometrics.dart';

/// #066 — biometric unlock must never throw or claim success when the platform
/// cannot provide it. The PIN stays the only guaranteed way in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('availability fails closed when no biometric plugin is present', () async {
    expect(await Biometrics.available(), isFalse);
  });

  test('a prompt fails closed instead of throwing', () async {
    expect(await Biometrics.prompt(), isFalse);
  });
}
