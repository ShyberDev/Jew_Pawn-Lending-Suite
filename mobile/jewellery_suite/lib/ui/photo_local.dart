// Platform-safe photo helpers.
//
// Native: reads real photo files from the device.
// Web (demo/preview mode): no persistent file system, so thumbnails fall
// back to placeholders and picked photos are not stored.
export 'photo_local_stub.dart' if (dart.library.js_interop) 'photo_local_web.dart';