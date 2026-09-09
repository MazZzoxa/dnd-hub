import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/constants/dnd_data.dart';
import '../../../data/models/spell_model.dart';
import '../../../domain/providers/character_provider.dart';
import '../../../domain/providers/spell_provider.dart';
import '../../../domain/providers/spell_slot_provider.dart';

const _castingTimes = [
  '1 действие',
  '1 бонусное действие',
  '1 реакция',
  '1 минута',
  '10 минут',
  '1 час',
  'Другое',
];

String _localizedComponents(String value) {
  if (value.trim().isEmpty) return '';
  var result = value;
  result = result.replaceAll(RegExp(r'(?<![A-Za-zА-Яа-я])V(?![A-Za-zА-Яа-я])'), 'В');
  result = result.replaceAll(RegExp(r'(?<![A-Za-zА-Яа-я])S(?![A-Za-zА-Яа-я])'), 'С');
  result = result.replaceAll(RegExp(r'(?<![A-Za-zА-Яа-я])M(?![A-Za-zА-Яа-я])'), 'М');
  return result;
}

/// Раздел заклинаний — см. п.17 ТЗ.
/// Задача первой версии: удобно хранить и быстро находить заклинания,
/// плюс отслеживать ячейки заклинаний и заклинательную статистику
/// (класс/характеристика/Сложность спасения/бонус атаки), как на листе Aternia.
class SpellsSection extends StatefulWidget {
  const SpellsSection({super.key});

  @override
  State<SpellsSection> createState() => _SpellsSectionState();
}

class _SpellsSectionState extends State<SpellsSection> {
  int? _loadedForCharacterId;

  @override
  Widget build(BuildContext context) {
    final characterId = context.watch<CharacterProvider>().selected?.id;
    if (characterId == null) {
      return const Center(child: Text('Персонаж не выбран'));
    }
    if (_loadedForCharacterId != characterId) {
      _loadedForCharacterId = characterId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<SpellProvider>().loadForCharacter(characterId);
        context.read<SpellSlotProvider>().loadForCharacter(characterId);
      });
    }

    return Consumer<SpellProvider>(
      builder: (context, provider, _) {
        if (provider.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final byLevel = provider.spellsByLevel;
        final levels = byLevel.keys.toList()..sort();

        return Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              children: [
                const _SpellcastingHeader(),
                const SizedBox(height: 16),
                const _SectionLabel('Ячейки заклинаний'),
                const SizedBox(height: 10),
                const _SpellSlotsGrid(),
                const SizedBox(height: 20),
                const _SectionLabel('Известные заклинания'),
                const SizedBox(height: 10),
                if (provider.spells.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('Заклинания ещё не добавлены',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  )
                else
                  for (final level in levels)
                    _LevelBlock(
                      level: level,
                      spells: byLevel[level]!,
                      characterId: characterId,
                    ),
              ],
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: FloatingActionButton(
                onPressed: () => _showSpellDialog(context, characterId: characterId),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showSpellDialog(
    BuildContext context, {
    required int characterId,
    SpellModel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final levelController = TextEditingController(text: '${existing?.level ?? 0}');
    final typeController = TextEditingController(text: existing?.type ?? '');
    final rangeController = TextEditingController(text: existing?.range ?? '');
    final componentsController = TextEditingController(text: _localizedComponents(existing?.components ?? ''));
    String castingTime = existing?.castingTime ?? '';
    final durationController = TextEditingController(text: existing?.duration ?? '');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    bool prepared = existing?.prepared ?? false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Новое заклинание' : 'Изменить заклинание'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Название'),
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: levelController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Уровень (0 = заговор)'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'Школа/тип'),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: rangeController,
                      decoration: const InputDecoration(labelText: 'Дальность'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: castingTime.isEmpty ? null : castingTime,
                      decoration: const InputDecoration(labelText: 'Время накладывания'),
                      items: [
                        ..._castingTimes.map((value) =>
                            DropdownMenuItem(value: value, child: Text(value))),
                        if (castingTime.isNotEmpty && !_castingTimes.contains(castingTime))
                          DropdownMenuItem(value: castingTime, child: Text(castingTime)),
                      ],
                      onChanged: (value) => setState(() => castingTime = value ?? ''),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                TextField(
                  controller: durationController,
                  decoration: const InputDecoration(labelText: 'Длительность'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: componentsController,
                  decoration: const InputDecoration(labelText: 'Компоненты (В, С, М)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Описание'),
                  maxLines: 3,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Подготовлено'),
                  value: prepared,
                  onChanged: (value) => setState(() => prepared = value),
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () {
                  context.read<SpellProvider>().deleteSpell(existing.id!);
                  Navigator.of(context).pop(false);
                },
                child: const Text('Удалить', style: TextStyle(color: AppTheme.danger)),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !context.mounted) return;
    if (nameController.text.trim().isEmpty) return;

    final spell = SpellModel(
      id: existing?.id,
      characterId: characterId,
      name: nameController.text.trim(),
      level: int.tryParse(levelController.text.trim()) ?? 0,
      type: typeController.text.trim(),
      range: rangeController.text.trim(),
      components: componentsController.text.trim(),
      castingTime: castingTime,
      duration: durationController.text.trim(),
      description: descriptionController.text.trim(),
      prepared: prepared,
    );

    final provider = context.read<SpellProvider>();
    if (existing == null) {
      await provider.addSpell(spell);
    } else {
      await provider.updateSpell(spell);
    }
  }
}

/// Класс заклинателя, базовая характеристика, Сложность спасения и бонус
/// атаки заклинанием — верхний блок страницы заклинаний на листе Aternia.
class _SpellcastingHeader extends StatelessWidget {
  const _SpellcastingHeader();

  @override
  Widget build(BuildContext context) {
    return Consumer<CharacterProvider>(
      builder: (context, provider, _) {
        final character = provider.selected!;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _dropdownField(
                      context,
                      label: 'Базовая характеристика',
                      value: character.spellcastingAbility.isEmpty
                          ? null
                          : character.spellcastingAbility,
                      onChanged: (value) => provider.updateCharacter(
                          character.copyWith(spellcastingAbility: value ?? '')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatMini(
                        label: 'Сложность спасения', value: '${character.spellSaveDC}'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatMini(
                        label: 'Бонус атаки',
                        value: character.spellAttackBonus >= 0
                            ? '+${character.spellAttackBonus}'
                            : '${character.spellAttackBonus}'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dropdownField(
    BuildContext context, {
    required String label,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: [
        const DropdownMenuItem(value: null, child: Text('—')),
        for (final ability in kAbilities)
          DropdownMenuItem(value: ability.key, child: Text(ability.shortLabel)),
      ],
      onChanged: onChanged,
    );
  }
}

class _StatMini extends StatelessWidget {
  final String label;
  final String value;
  const _StatMini({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            textAlign: TextAlign.center),
      ],
    );
  }
}

/// Сетка ячеек заклинаний по уровням 1-9: всего / потрачено.
class _SpellSlotsGrid extends StatelessWidget {
  const _SpellSlotsGrid();

  @override
  Widget build(BuildContext context) {
    return Consumer<SpellSlotProvider>(
      builder: (context, provider, _) {
        return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: List.generate(9, (i) {
            final level = i + 1;
            final slot = provider.slotFor(level);
            return Container(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Уровень $level',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => provider.adjustUsed(level, -1),
                        child: const Icon(Icons.remove, size: 16, color: AppTheme.accent),
                      ),
                      const SizedBox(width: 8),
                      Text('${slot.used}/${slot.total}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => provider.adjustUsed(level, 1),
                        child: const Icon(Icons.add, size: 16, color: AppTheme.accent),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => _editTotal(context, provider, level, slot.total),
                    child: const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('изм. всего',
                          style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                    ),
                  ),
                ],
              ),
            );
          }),
        );
      },
    );
  }

  Future<void> _editTotal(
      BuildContext context, SpellSlotProvider provider, int level, int currentTotal) async {
    final controller = TextEditingController(text: '$currentTotal');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Всего ячеек — уровень $level'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(int.tryParse(controller.text.trim())),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result != null) {
      await provider.setTotal(level, result);
    }
  }
}

class _LevelBlock extends StatelessWidget {
  final int level;
  final List<SpellModel> spells;
  final int characterId;

  const _LevelBlock({required this.level, required this.spells, required this.characterId});

  @override
  Widget build(BuildContext context) {
    final title = level == 0 ? 'Заговоры' : 'Уровень $level';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (int i = 0; i < spells.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    onTap: () => _SpellsSectionState._showSpellDialog(
                      context,
                      characterId: characterId,
                      existing: spells[i],
                    ),
                    leading: Icon(
                      spells[i].prepared ? Icons.auto_fix_high : Icons.auto_fix_normal_outlined,
                      color: spells[i].prepared ? AppTheme.accent : AppTheme.textSecondary,
                    ),
                    title: Text(spells[i].name),
                    subtitle: Text([
                      if (spells[i].type.isNotEmpty) spells[i].type,
                      if (spells[i].range.isNotEmpty) spells[i].range,
                      if (spells[i].castingTime.isNotEmpty) spells[i].castingTime,
                      if (spells[i].components.isNotEmpty)
                        _localizedComponents(spells[i].components),
                    ].join(' · ')),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5));
  }
}
