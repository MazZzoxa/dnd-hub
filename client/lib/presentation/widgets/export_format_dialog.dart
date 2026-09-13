import 'package:flutter/material.dart';

import '../../data/export/export_manager.dart';

Future<ExportFileFormat?> showExportFormatDialog(BuildContext context) {
  return showDialog<ExportFileFormat>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Экспорт'),
      content: const Text('Выберите формат файла'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(ExportFileFormat.json),
          child: const Text('JSON'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(ExportFileFormat.dndhub),
          child: const Text('.dndhub'),
        ),
      ],
    ),
  );
}
