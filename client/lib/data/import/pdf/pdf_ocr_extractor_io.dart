import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_ocr_native/flutter_ocr_native.dart';

import 'pdf_ocr_windows.dart';

/// OCR adapter.
///
/// Windows deliberately bypasses flutter_ocr_native's OCR recognition path:
/// that plugin currently filters non-Latin scripts and its Windows engine is
/// initialized with en-US first. For Russian / mixed-language character sheets
/// this causes severe information loss. We still reuse its native PDF renderer
/// on Windows, then run the app's Windows.Media.Ocr bridge on each rendered page.
class PdfOcrExtractor {
  Future<String> extract(Uint8List bytes) async {
    if (Platform.isWindows) {
      return _extractWindows(bytes);
    }

    final reader = OcrReader(
      validateDocument: false,
      maskAadhaar: false,
    );

    try {
      final result = await reader.readFromPdf(bytes);
      if (result == null || result.text.trim().isEmpty) {
        throw const PdfOcrException(
          'OCR не смог распознать текст в PDF на этой платформе.',
        );
      }
      return result.text;
    } catch (e) {
      if (e is PdfOcrException) rethrow;
      throw PdfOcrException('Не удалось выполнить локальный OCR PDF: $e');
    } finally {
      await reader.dispose();
    }
  }

  Future<String> _extractWindows(Uint8List pdfBytes) async {
    final pageCount = await OcrDocumentSaver.getPdfPageCount(pdfBytes);
    if (pageCount <= 0) {
      throw const PdfOcrException('Не удалось определить страницы PDF для OCR.');
    }

    final pages = <String>[];
    for (var page = 0; page < pageCount; page++) {
      final image = await OcrDocumentSaver.renderPdfPage(
        pdfBytes,
        page: page,
        scale: 2.5,
      );
      if (image == null || image.isEmpty) continue;

      try {
        final text = await WindowsPdfOcr.recognize(image);
        if (text.trim().isNotEmpty) {
          pages.add(text.trim());
        }
      } on WindowsPdfOcrException catch (e) {
        throw PdfOcrException('Ошибка Windows OCR на странице ${page + 1}: ${e.message}');
      }
    }

    final result = pages.join('\n\n');
    if (result.trim().isEmpty) {
      throw const PdfOcrException('OCR не смог распознать текст ни на одной странице PDF.');
    }
    return result;
  }
}

class PdfOcrException implements Exception {
  final String message;
  const PdfOcrException(this.message);

  @override
  String toString() => message;
}
