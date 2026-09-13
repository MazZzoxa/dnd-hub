import 'package:flutter/material.dart';

import '../../data/import/import_manager.dart';
import 'import_preview_dialog.dart';

/// Универсальный "Импорт по ссылке" (docs/D&D Hub.md, п.25): пользователь
/// вставляет один URL, программа сама определяет тип содержимого, показывает
/// предпросмотр и импортирует после подтверждения.
Future<ImportResult?> showImportUrlDialog(BuildContext context) async {
  final url = await showDialog<String>(
    context: context,
    builder: (dialogContext) => const _PasteUrlDialog(),
  );
  if (url == null || url.trim().isEmpty || !context.mounted) return null;

  final manager = ImportManager();
  late final ImportPreview preview;
  try {
    preview = await manager.previewUrl(url);
  } catch (error) {
    if (context.mounted) _showError(context, 'Не удалось проверить ссылку: $error');
    return null;
  }

  if (!context.mounted) return null;
  final confirmed = await showImportPreviewDialog(
    context,
    sourceLabel: url,
    preview: preview,
  );
  if (confirmed == null || !context.mounted) return null;

  try {
    final result = preview.importAction != null
        ? await preview.importAction!(confirmed)
        : await manager.importUrl(url);
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

class _PasteUrlDialog extends StatefulWidget {
  const _PasteUrlDialog();

  @override
  State<_PasteUrlDialog> createState() => _PasteUrlDialogState();
}

class _PasteUrlDialogState extends State<_PasteUrlDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт по ссылке'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(
          hintText: 'https://...',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Далее'),
        ),
      ],
    );
  }
}
