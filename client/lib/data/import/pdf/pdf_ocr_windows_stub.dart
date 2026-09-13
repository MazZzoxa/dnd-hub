import 'dart:typed_data';

class WindowsPdfOcr {
  static Future<String> recognize(Uint8List imageBytes) {
    throw UnsupportedError('Windows OCR is only available on Windows.');
  }
}
