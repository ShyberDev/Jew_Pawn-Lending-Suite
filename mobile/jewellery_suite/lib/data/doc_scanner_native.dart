import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

/// Opens Google's document scanner (the same flow Google Drive uses): it
/// detects the document edges, crops and straightens the page automatically and
/// can also import an existing photo from the gallery with the same automatic
/// trim. Returns the path of the scanned JPEG, or null when the scanner is not
/// available on the device — the caller then falls back to the plain camera.
Future<String?> captureDocument() async {
  final options = DocumentScannerOptions(
    documentFormats: const {DocumentFormat.jpeg},
    // filter = auto-crop / enhance / rotate, exactly the Drive behaviour.
    mode: ScannerMode.filter,
    pageLimit: 1,
    isGalleryImport: true,
  );
  DocumentScanner? scanner;
  try {
    scanner = DocumentScanner(options: options);
    final result = await scanner.scanDocument();
    final images = result.images;
    if (images == null || images.isEmpty) return null;
    return images.first;
  } catch (_) {
    // No Play services / scanner unavailable — the caller falls back.
    return null;
  } finally {
    await scanner?.close();
  }
}
