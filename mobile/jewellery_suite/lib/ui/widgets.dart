import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'palette.dart';
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

/// v1.0.9: compact photo picker — a thumbnail plus **camera and gallery
/// symbols only** (no "Camera"/"Gallery" text), so forms stay narrow on
/// big-font phones.
class PhotoIconPicker extends StatelessWidget {
  const PhotoIconPicker({
    super.key,
    this.path,
    required this.onPicked,
    this.onCleared,
    this.size = 58,
  });

  final String? path;
  final ValueChanged<String> onPicked;
  final VoidCallback? onCleared;
  final double size;

  Future<void> _choose(ImageSource source) async {
    final saved = await pickAndStoreImage(source);
    if (saved != null) onPicked(saved);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            border: Border.all(color: lineOf(context)),
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.antiAlias,
          child: photoThumb(path,
              width: size, height: size, fit: BoxFit.cover,
              fallback: Icon(Icons.image_outlined,
                  size: 22, color: mutedOf(context))),
        ),
        const SizedBox(width: 6),
        // Camera symbol
        IconButton(
          tooltip: 'Camera',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.photo_camera_outlined, color: kGoldDark),
          onPressed: () => _choose(ImageSource.camera),
        ),
        // Gallery symbol
        IconButton(
          tooltip: 'Gallery',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.photo_library_outlined, color: kGoldDark),
          onPressed: () => _choose(ImageSource.gallery),
        ),
        if (path != null && onCleared != null)
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCleared,
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

// ---------------------------------------------------------------------------
// Drag-to-delete (v1.0.8): long-press a tile to lift it, drag it onto the
// bottom trash bin and the bin runs the tile's delete action. Long-pressing
// alone never deletes (pocket-safe).
// ---------------------------------------------------------------------------

/// What a dragged tile does when dropped on the trash bin. Each screen builds
/// its own payload so deleting a khata / member / ledger row can show its own
/// confirmation (admin password for khata + members, none for ledger rows).
class DeletePayload {
  const DeletePayload({required this.drop});

  /// Performs the delete. Return true when actually deleted.
  final Future<bool> Function() drop;
}

/// Wraps a tile so it can be lifted with a long-press and dragged to the bin.
class DragToDeleteTile extends StatelessWidget {
  const DragToDeleteTile({
    super.key,
    required this.payload,
    required this.child,
    this.onDragChanged,
  });

  final DeletePayload payload;
  final Widget child;

  /// Called with true when a drag starts and false when it ends, so the
  /// screen can show/hide the trash bin.
  final ValueChanged<bool>? onDragChanged;

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<DeletePayload>(
      data: payload,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => onDragChanged?.call(true),
      onDragEnd: (_) => onDragChanged?.call(false),
      onDraggableCanceled: (_, __) => onDragChanged?.call(false),
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      feedback: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: Opacity(opacity: 0.92, child: child),
      ),
      child: child,
    );
  }
}

/// Bottom-centre trash bin. Sit it in a `Stack` (e.g. `Align(
/// alignment: Alignment.bottomCenter, child: DeleteTrashTarget(...))`).
/// It stays invisible until a drag starts, then slides up; hovering a dragged
/// tile over it turns it red.
class DeleteTrashTarget extends StatelessWidget {
  const DeleteTrashTarget({
    super.key,
    required this.visible,
    required this.onDrop,
  });

  final bool visible;
  final Future<bool> Function(DeletePayload) onDrop;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.2),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: DragTarget<DeletePayload>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) => onDrop(details.data),
            builder: (context, candidates, _) {
              final hot = candidates.isNotEmpty;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                decoration: BoxDecoration(
                  color: hot ? kRed : kGoldDark,
                  borderRadius: BorderRadius.circular(40),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .25),
                        blurRadius: 14,
                        offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(hot ? Icons.delete : Icons.delete_outline,
                        color: Colors.white, size: 30),
                    const SizedBox(width: 10),
                    Text(
                      hot ? 'Release to delete' : 'Drag here to delete',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
