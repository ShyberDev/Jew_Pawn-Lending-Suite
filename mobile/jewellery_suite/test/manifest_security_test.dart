import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #080 security: the Android manifest must keep the shop's ledger off the
/// platform's backup and device-transfer paths. A missing `allowBackup` defaults
/// to **true**, which is how this was leaking in the first place, so the check is
/// explicit rather than implied.
void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('the app refuses platform backup', () {
    expect(manifest, contains('android:allowBackup="false"'),
        reason: 'without this, Android may copy the encrypted ledger to the cloud');
    expect(manifest, contains('android:fullBackupContent="false"'));
  });

  test('Android 12+ extraction rules exclude everything', () {
    expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    final rules =
        File('android/app/src/main/res/xml/data_extraction_rules.xml')
            .readAsStringSync();
    expect(rules, contains('<cloud-backup>'));
    expect(rules, contains('<device-transfer>'));
    expect(rules, contains('domain="database"'));
    expect(rules, contains('domain="sharedpref"'));
  });
}
