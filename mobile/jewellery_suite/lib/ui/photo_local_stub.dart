import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// True when a real photo file exists at [path] (native only).
bool photoExists(String path) => path.isNotEmpty && File(path).existsSync();

/// Renders the photo file, or [fallback] when it is missing.
Widget photoThumb(String? path,
    {double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    Widget fallback = const SizedBox.shrink()}) {
  if (path == null || !photoExists(path)) return fallback;
  return Image.file(File(path), width: width, height: height, fit: fit);
}

/// ImageProvider variant for CircleAvatar-style backgrounds.
ImageProvider? photoProvider(String path) =>
    photoExists(path) ? FileImage(File(path)) : null;

/// Copies a picked photo into the app documents folder so it survives the
/// picker cache being cleared; returns the stored path (native only).
Future<String?> storePickedPhoto(String srcPath, String name) async {
  final dir = await getApplicationDocumentsDirectory();
  final photosDir = Directory(p.join(dir.path, 'photos'));
  if (!await photosDir.exists()) await photosDir.create(recursive: true);
  final target = p.join(photosDir.path,
      '${DateTime.now().millisecondsSinceEpoch}_${p.basename(srcPath)}');
  await File(srcPath).copy(target);
  return target;
}