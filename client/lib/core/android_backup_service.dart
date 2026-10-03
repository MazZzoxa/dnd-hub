import 'dart:io';

import 'package:flutter/services.dart';

/// Requests Android Auto Backup to refresh its snapshot of the app data.
///
/// The request is intentionally best-effort: Android schedules the actual
/// backup pass when the system considers it appropriate. On non-Android
/// platforms the method is a no-op.
class AndroidBackupService {
  AndroidBackupService._();

  static const MethodChannel _channel = MethodChannel('dnd_hub/android_backup');

  static Future<void> dataChanged() async {
    if (!Platform.isAndroid) return;

    try {
      await _channel.invokeMethod<bool>('dataChanged');
    } on MissingPluginException {
      // The native Android bridge is unavailable on another platform/build.
    } on PlatformException catch (error) {
      // Backup is best-effort and must never break normal app data operations.
      // Keep the exception out of the user-facing restore flow.
      // ignore: avoid_print
      print('D&D Hub Android Backup warning: ${error.message}');
    }
  }
}
