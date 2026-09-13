import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/import/import_manager.dart';
import 'import_preview_dialog.dart';

/// Выбирает JSON/.dndhub/PDF-файл, показывает краткое содержимое,
/// затем выполняет импорт после подтверждения.
Future<ImportResult?> showImportFileDialog(BuildContext context) async {
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json', 'dndhub', 'pdf'],
    withData: true,
  );
  if (picked == null || picked.files.isEmpty || !context.mounted) return null;

  final file = picked.files.single;
  final bytes = file.bytes;
  if (bytes == null) {
    _showError(context, 'Не удалось прочитать выбранный файл.');
    return null;
  }

  final manager = ImportManager();
  late final ImportPreview preview;
  try {
    preview = file.extension?.toLowerCase() == 'pdf'
        ? await manager.previewPdfBytes(Uint8List.fromList(bytes))
        : manager.previewBytes(Uint8List.fromList(bytes));
  } catch (error) {
    if (context.mounted) _showError(context, 'Не удалось проверить файл: $error');
    return null;
  }

  final confirmed = await showImportPreviewDialog(
    context,
    sourceLabel: file.name,
    preview: preview,
  );
  if (confirmed == null || !context.mounted) return null;

  try {
    final result = preview.importAction != null
        ? await preview.importAction!(confirmed)
        : file.extension?.toLowerCase() == 'pdf'
            ? await manager.importPdfBytes(Uint8List.fromList(bytes))
            : await manager.importBytes(Uint8List.fromList(bytes));
    if (!context.mounted) return result;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Импортировано: ${result.title}')),
    );
    return result;
  } catch (error) {
    if (context.mounted) _showError(context, 'Импорт не выполнен: $error');
    return null;
  }
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
