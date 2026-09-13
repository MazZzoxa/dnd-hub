import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Общий bottom sheet "Создать вручную" / "Добавить из библиотеки".
///
/// Используется в разделах Inventory/Spells/Abilities персонажа — см.
/// docs/D&D Hub.md п.23: пользователь должен иметь выбор между созданием
/// объекта с нуля и добавлением готового из Local Content Library.
Future<void> showAddOptionsSheet(
  BuildContext context, {
  required VoidCallback onManual,
  required VoidCallback onFromLibrary,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Создать вручную'),
            onTap: () {
              Navigator.of(context).pop();
              onManual();
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('Добавить из библиотеки'),
            onTap: () {
              Navigator.of(context).pop();
              onFromLibrary();
            },
          ),
        ],
      ),
    ),
  );
}
