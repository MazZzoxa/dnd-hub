import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/ability_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/spell_model.dart';
import '../../data/repositories/ability_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/spell_repository.dart';
import '../../data/services/character_library_service.dart';

/// Диалог для переноса существующих предметов персонажа в Local Library.
/// Возвращает количество новых объектов, добавленных в библиотеку.
Future<int?> showCharacterLibraryAddDialog(
  BuildContext context, {
  required int characterId,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _CharacterLibraryAddDialog(characterId: characterId),
  );
}

class _CharacterLibraryAddDialog extends StatefulWidget {
  final int characterId;

  const _CharacterLibraryAddDialog({required this.characterId});

  @override
  State<_CharacterLibraryAddDialog> createState() => _CharacterLibraryAddDialogState();
}

class _CharacterLibraryAddDialogState extends State<_CharacterLibraryAddDialog> {
  final _inventoryRepository = InventoryRepository();
  final _spellRepository = SpellRepository();
  final _abilityRepository = AbilityRepository();
  final _service = CharacterLibraryService();

  List<ItemModel> _items = const [];
  List<SpellModel> _spells = const [];
  List<AbilityModel> _abilities = const [];
  bool _loading = true;
  final Set<String> _processing = <String>{};
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        _inventoryRepository.getForCharacter(widget.characterId),
        _spellRepository.getForCharacter(widget.characterId),
        _abilityRepository.getForCharacter(widget.characterId),
      ]);
      if (!mounted) return;
      setState(() {
        _items = results[0] as List<ItemModel>;
        _spells = results[1] as List<SpellModel>;
        _abilities = results[2] as List<AbilityModel>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось загрузить объекты персонажа: $error')),
      );
    }
  }

  Future<void> _addItem(ItemModel item) async {
    final key = 'item:${item.id}';
    if (_processing.contains(key)) return;
    setState(() => _processing.add(key));
    try {
      final libraryItem = await _service.addItem(item);
      final index = _items.indexWhere((value) => value.id == item.id);
      if (index != -1 && item.libraryItemId == null) {
        final updated = item.copyWith(libraryItemId: libraryItem.id);
        _items = [..._items]..[index] = updated;
        _addedCount++;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось добавить предмет: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing.remove(key));
    }
  }

  Future<void> _addSpell(SpellModel spell) async {
    final key = 'spell:${spell.id}';
    if (_processing.contains(key)) return;
    setState(() => _processing.add(key));
    try {
      final libraryItem = await _service.addSpell(spell);
      final index = _spells.indexWhere((value) => value.id == spell.id);
      if (index != -1 && spell.libraryItemId == null) {
        final updated = spell.copyWith(libraryItemId: libraryItem.id);
        _spells = [..._spells]..[index] = updated;
        _addedCount++;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось добавить заклинание: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing.remove(key));
    }
  }

  Future<void> _addAbility(AbilityModel ability) async {
    final key = 'ability:${ability.id}';
    if (_processing.contains(key)) return;
    setState(() => _processing.add(key));
    try {
      final libraryItem = await _service.addAbility(ability);
      final index = _abilities.indexWhere((value) => value.id == ability.id);
      if (index != -1 && ability.libraryItemId == null) {
        final updated = ability.copyWith(libraryItemId: libraryItem.id);
        _abilities = [..._abilities]..[index] = updated;
        _addedCount++;
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось добавить способность: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _processing.remove(key));
    }
  }

  Widget _section<T>({
    required String title,
    required IconData icon,
    required List<T> entries,
    required String Function(T value) name,
    required int? Function(T value) libraryId,
    required Future<void> Function(T value) onAdd,
  }) {
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        for (final entry in entries)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: Text(name(entry)),
            trailing: libraryId(entry) != null
                ? const Tooltip(
                    message: 'Уже в библиотеке',
                    child: Icon(Icons.check_circle, color: AppTheme.success),
                  )
                : IconButton(
                    tooltip: 'Добавить в библиотеку',
                    icon: const Icon(Icons.library_add_outlined),
                    onPressed: () => onAdd(entry),
                  ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final contentWidth = (screen.width - 32).clamp(280.0, 560.0);
    final contentHeight = (screen.height * 0.68).clamp(320.0, 520.0);

    return AlertDialog(
      title: const Text('Добавить в библиотеку'),
      content: SizedBox(
        width: contentWidth,
        height: contentHeight,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_items.isEmpty && _spells.isEmpty && _abilities.isEmpty)
                ? const Center(
                    child: Text(
                      'На персонаже пока нет предметов, заклинаний или способностей.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView(
                    children: [
                      _section<ItemModel>(
                        title: 'Предметы',
                        icon: Icons.backpack_outlined,
                        entries: _items,
                        name: (value) => value.name,
                        libraryId: (value) => value.libraryItemId,
                        onAdd: _addItem,
                      ),
                      _section<SpellModel>(
                        title: 'Заклинания',
                        icon: Icons.auto_fix_normal_outlined,
                        entries: _spells,
                        name: (value) => value.name,
                        libraryId: (value) => value.libraryItemId,
                        onAdd: _addSpell,
                      ),
                      _section<AbilityModel>(
                        title: 'Способности',
                        icon: Icons.bolt_outlined,
                        entries: _abilities,
                        name: (value) => value.name,
                        libraryId: (value) => value.libraryItemId,
                        onAdd: _addAbility,
                      ),
                    ],
                  ),
      ),
      actions: [
        if (_addedCount > 0)
          Text(
            'Добавлено: $_addedCount',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_addedCount),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
