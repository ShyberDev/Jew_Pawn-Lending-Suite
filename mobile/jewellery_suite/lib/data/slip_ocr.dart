// Slip scanning (New Pawn Loan → Scan). On the phone this runs on-device OCR
// (ML Kit, Latin script); in the web preview there is no OCR, so a scan simply
// reports nothing found and the form stays fully usable by hand.
export 'slip_ocr_native.dart' if (dart.library.js_interop) 'slip_ocr_stub.dart';
