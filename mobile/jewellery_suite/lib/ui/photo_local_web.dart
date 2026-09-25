import 'package:flutter/material.dart';

/// Web demo/preview mode: no persistent photo files exist.
bool photoExists(String path) => false;

/// Always renders [fallback] on web.
Widget photoThumb(String? path,
    {double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget fallback = const SizedBox.shrink()}) {
  return fallback;
}

ImageProvider? photoProvider(String path) => null;

/// Web: picked photos are not persisted in demo mode.
Future<String?> storePickedPhoto(String srcPath, String name) async => null;