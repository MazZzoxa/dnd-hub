import 'dart:typed_data';

class PdfOcrExtractor {
  Future<String> extract(Uint8List bytes) async {
    throw const PdfOcrException(
      'Локальный OCR для этой платформы пока не поддерживается.',
    );
  }
}

class PdfOcrException implements Exception {
  final String message;
  const PdfOcrException(this.message);

  @override
  String toString() => message;
}
