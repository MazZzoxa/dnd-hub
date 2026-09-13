import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/providers/character_provider.dart';
import '../../domain/providers/inventory_provider.dart';
import '../../domain/providers/spell_provider.dart';
import '../../domain/providers/ability_provider.dart';
import '../../data/export/export_manager.dart';
import '../../data/models/character_model.dart';
import '../widgets/export_format_dialog.dart';
import '../widgets/character_library_add_dialog.dart';
import 'sections/abilities_section.dart';
import 'sections/bio_section.dart';
import 'sections/inventory_section.dart';
import 'sections/notes_section.dart';
import 'sections/overview_section.dart';
import 'sections/settings_section.dart';
import 'sections/spells_section.dart';

/// Главная "оболочка" персонажа: на телефоне — нижняя навигация,
/// на широком экране (PC) — боковая панель (NavigationRail), как
/// показано в мокапах п.12 ТЗ. Оба режима переиспользуют одни и те же
/// виджеты разделов, поэтому логика не дублируется.
class CharacterHomeScreen extends StatefulWidget {
  const CharacterHomeScreen({super.key});

  @override
  State<CharacterHomeScreen> createState() => _CharacterHomeScreenState();
}

class _CharacterHomeScreenState extends State<CharacterHomeScreen> {
  int _index = 0;

  static const _destinations = [
    (icon: Icons.shield_outlined, selectedIcon: Icons.shield, label: 'Обзор'),
    (icon: Icons.backpack_outlined, selectedIcon: Icons.backpack, label: 'Инвентарь'),
    (icon: Icons.auto_fix_normal_outlined, selectedIcon: Icons.auto_fix_high, label: 'Заклинания'),
    (icon: Icons.bolt_outlined, selectedIcon: Icons.bolt, label: 'Способности'),
    (icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Био'),
    (icon: Icons.notes_outlined, selectedIcon: Icons.notes, label: 'Заметки'),
    (icon: Icons.settings_outlined, selectedIcon: Icons.settings, label: 'Настройки'),
  ];

  Widget _body(int index) {
    switch (index) {
      case 0:
        return const OverviewSection();
      case 1:
        return const InventorySection();
      case 2:
        return const SpellsSection();
      case 3:
        return const AbilitiesSection();
      case 4:
        return const BioSection();
      case 5:
        return const NotesSection();
      case 6:
      default:
        return SettingsSection(onCharacterDeleted: () => Navigator.of(context).pop());
    }
  }

  Future<void> _exportCharacter(BuildContext context, CharacterModel character) async {
    final format = await showExportFormatDialog(context);
    if (format == null || !context.mounted) return;

    try {
      final fileName = await ExportManager().exportCharacter(character, format: format);
      if (!context.mounted || fileName == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Экспортировано: $fileName')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать: $error')),
      );
    }
  }


  Future<void> _addToLibrary(BuildContext context, CharacterModel character) async {
    final added = await showCharacterLibraryAddDialog(
      context,
      characterId: character.id!,
    );
    if (!context.mounted || added == null || added == 0) return;

    // Обновляем разделы, чтобы новые libraryItemId сразу были видны,
    // когда пользователь переключится на инвентарь/заклинания/способности.
    await Future.wait([
      context.read<InventoryProvider>().loadForCharacter(character.id!),
      context.read<SpellProvider>().loadForCharacter(character.id!),
      context.read<AbilityProvider>().loadForCharacter(character.id!),
    ]);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено в библиотеку: $added')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final character = context.watch<CharacterProvider>().selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(character?.name ?? 'D&D Hub'),
        actions: [
          if (character != null) ...[
            IconButton(
              icon: const Icon(Icons.library_add_outlined),
              tooltip: 'Добавить в библиотеку',
              onPressed: () => _addToLibrary(context, character),
            ),
            IconButton(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: 'Экспортировать персонажа',
              onPressed: () => _exportCharacter(context, character),
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;
          if (isWide) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (value) => setState(() => _index = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selectedIcon),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _body(_index)),
              ],
            );
          }
          return _body(_index);
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 800;
          if (isWide) return const SizedBox.shrink();
          return BottomNavigationBar(
            currentIndex: _index,
            onTap: (value) => setState(() => _index = value),
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 10,
            unselectedFontSize: 10,
            items: [
              for (final d in _destinations)
                BottomNavigationBarItem(icon: Icon(d.icon), label: d.label),
            ],
          );
        },
      ),
    );
  }
}
