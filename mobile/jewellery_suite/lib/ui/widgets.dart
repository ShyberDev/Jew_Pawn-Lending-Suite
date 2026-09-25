import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'photo_local.dart';

/// Returns a [FileImage] when [path] exists on disk (mobile only).
ImageProvider? awaitFileImage(String path) {
  if (kIsWeb) return null;
  final file = File(path);
  if (file.existsSync()) return FileImage(file);
  return null;
}

/// Picks an image and copies it into the app's documents folder so it survives
/// the image_picker cache being cleared.
Future<String?> pickAndStoreImage(ImageSource source) async {
  final picked = await ImagePicker().pickImage(
    source: source,
    imageQuality: 70,
    maxWidth: 1600,
  );
  if (picked == null) return null;
  if (kIsWeb) return null; // web preview: photos are not persisted
  return storePickedPhoto(picked.path, picked.name);
}

/// A tap-to-capture / pick photo widget with a preview.
class PhotoField extends StatelessWidget {
  const PhotoField({super.key, this.path, required this.onPicked, this.label = 'Photo'});

  final String? path;
  final ValueChanged<String> onPicked;
  final String label;

  Future<void> _choose(BuildContext context, ImageSource source) async {
    final saved = await pickAndStoreImage(source);
    if (saved != null) onPicked(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: photoThumb(path, width: 76, height: 76, fit: BoxFit.cover,
              fallback: Icon(Icons.photo_camera_outlined,
                  size: 30, color: Theme.of(context).hintColor)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_camera, size: 18),
                label: const Text('Camera'),
                onPressed: () => _choose(context, ImageSource.camera),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library, size: 18),
                label: const Text('Gallery'),
                onPressed: () => _choose(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

InputDecoration fieldDecoration(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
    );

String moneyText(num? value) => (value ?? 0).toStringAsFixed(2);

String todayIso() => DateTime.now().toIso8601String().substring(0, 10);

/// A simple card wrapper used across the forms.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

Future<bool> confirmDialog(BuildContext context, String message,
    {String title = 'Confirm'}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK')),
      ],
    ),
  );
  return result ?? false;
}
