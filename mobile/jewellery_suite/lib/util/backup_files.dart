import 'dart:io';

import 'package:flutter/services.dart';

/// Android file pickers for backups.
///
/// The app keeps its working backups in its private folder, which is wiped on
/// uninstall. Two system dialogs close that gap without any storage permission:
///
/// * [saveCopy] asks Android where to put a copy (Downloads, Drive, a USB
///   stick) using the Storage Access Framework's "create document" picker.
/// * [pickBackup] opens a `.zip` from anywhere and returns a private cache path
///   that the caller validates and copies into the backup folder.
///
/// Both return an empty result on hosts without the channel (tests, web,
/// desktop), so callers fall back to the share sheet instead of crashing.
class BackupFiles {
  const BackupFiles._();

  static const channel =
      MethodChannel('com.shyberdev.jewellery_suite/backup_files');

  /// True when the platform channel is available. Tests run on Linux, where it
  /// is not — the UI then keeps the share-sheet path only.
  static bool get supported => Platform.isAndroid;

  /// Outcome of [saveCopy].
  ///
  /// * `saved` — the copy was written to the chosen place.
  /// * `cancelled` — the shopkeeper closed the picker.
  /// * `failed` — Android could not write the file.
  /// * `unavailable` — not an Android host.
  static Future<String> saveCopy(String path, String fileName) async {
    if (!Platform.isAndroid) return 'unavailable';
    try {
      final value = await channel.invokeMethod<String>(
          'exportBackup', {'path': path, 'name': fileName});
      return value ?? 'failed';
    } catch (_) {
      return 'failed';
    }
  }

  /// Runs the system file picker and returns the path of a cached copy of the
  /// chosen archive, or null when the picker was closed or is unavailable.
  static Future<String?> pickBackup() async {
    if (!Platform.isAndroid) return null;
    try {
      return await channel.invokeMethod<String>('pickBackup');
    } catch (_) {
      return null;
    }
  }
}
