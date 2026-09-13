import 'package:flutter/material.dart';

import '../../data/models/library_item_model.dart';

/// Локализованные подписи и иконки для типов объектов Local Content
/// Library (см. docs/D&D Hub.md п.20, 68).
///
/// Вынесено в отдельный файл, чтобы переиспользовать не только на экране
/// библиотеки, но и в будущем экране "Добавить из библиотеки" на листе
/// персонажа (п.23 ТЗ).
class LibraryTypeLabels {
  LibraryTypeLabels._();

  static const Map<LibraryItemType, String> _plural = {
    LibraryItemType.item: 'Предметы',
    LibraryItemType.spell: 'Заклинания',
    LibraryItemType.ability: 'Способности',
    LibraryItemType.other: 'Другое',
  };

  static const Map<LibraryItemType, String> _singular = {
    LibraryItemType.item: 'Предмет',
    LibraryItemType.spell: 'Заклинание',
    LibraryItemType.ability: 'Способность',
    LibraryItemType.other: 'Другое',
  };

  static const Map<LibraryItemType, IconData> _icons = {
    LibraryItemType.item: Icons.backpack_outlined,
    LibraryItemType.spell: Icons.auto_fix_normal_outlined,
    LibraryItemType.ability: Icons.bolt_outlined,
    LibraryItemType.other: Icons.category_outlined,
  };

  static String plural(LibraryItemType type) => _plural[type] ?? type.name;
  static String singular(LibraryItemType type) => _singular[type] ?? type.name;
  static IconData icon(LibraryItemType type) => _icons[type] ?? Icons.circle_outlined;

  static String sourceLabel(LibrarySourceType sourceType) {
    switch (sourceType) {
      case LibrarySourceType.userCreated:
        return 'Создано вручную';
      case LibrarySourceType.imported:
        return 'Импортировано';
      case LibrarySourceType.local:
        return 'Встроенное';
    }
  }

  static IconData sourceIcon(LibrarySourceType sourceType) {
    switch (sourceType) {
      case LibrarySourceType.userCreated:
        return Icons.edit_outlined;
      case LibrarySourceType.imported:
        return Icons.file_download_outlined;
      case LibrarySourceType.local:
        return Icons.inventory_2_outlined;
    }
  }
}
