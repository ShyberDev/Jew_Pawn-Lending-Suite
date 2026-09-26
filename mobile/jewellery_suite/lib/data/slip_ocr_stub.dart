// Slip OCR — web preview fallback. No camera / no on-device text recognition
// in the web build, so scanning simply finds nothing and the form stays usable.
import 'slip_ocr_fields.dart';

export 'slip_ocr_fields.dart';

Future<SlipFields> scanSlipImage(String imagePath) async =>
    SlipFields.empty(imagePath);
