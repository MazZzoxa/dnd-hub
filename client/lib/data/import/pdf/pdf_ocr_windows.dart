import 'dart:typed_data';

import 'package:flutter/services.dart';

class WindowsPdfOcr {
  static const MethodChannel _channel = MethodChannel('dnd_hub/windows_ocr');

  static Future<String> recognize(Uint8List imageBytes) async {
    final result = await _channel.invokeMethod<String>('recognize', <String, Object>{
      'imageBytes': imageBytes,
    });
    if (result == null || result.trim().isEmpty) {
      throw const WindowsPdfOcrException('Windows OCR не вернул текст.');
    }
    return result;
  }
}

class WindowsPdfOcrException implements Exception {
  final String message;
  const WindowsPdfOcrException(this.message);

  @override
  String toString() => message;
}
