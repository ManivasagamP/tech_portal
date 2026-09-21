import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'nameplate_ocr.dart';

/// Runs on-device text recognition against a captured nameplate photo. The
/// heavy lifting — deciding what counts as manufacturer/model/serial — lives
/// in the testable [extractNameplateFields]; this class is just the camera
/// photo → recognized text plumbing.
class NameplateReader {
  final _recognizer = TextRecognizer();

  Future<NameplateFields> read(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final recognized = await _recognizer.processImage(input);
    return extractNameplateFields(recognized.text);
  }

  void dispose() => _recognizer.close();
}
