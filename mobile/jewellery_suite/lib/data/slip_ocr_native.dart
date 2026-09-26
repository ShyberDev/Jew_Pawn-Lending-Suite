import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'slip_ocr_fields.dart';
import 'slip_parser.dart';

export 'slip_ocr_fields.dart';

/// On-device OCR of a pawn slip photo (nothing leaves the phone). The recognised
/// text is mapped onto the New Pawn Loan form fields.
Future<SlipFields> scanSlipImage(String imagePath) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognized = await recognizer.processImage(inputImage);
    return parseSlipText(recognized.text);
  } finally {
    await recognizer.close();
  }
}
