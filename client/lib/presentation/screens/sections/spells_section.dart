import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/constants/dnd_data.dart';
import '../../../data/models/library_item_model.dart';
import '../../../data/models/spell_model.dart';
import '../../../data/models/spell_slot_model.dart';
import '../../../domain/providers/character_provider.dart';
import '../../../domain/providers/spell_provider.dart';
import '../../../domain/providers/spell_slot_provider.dart';
import '../../widgets/add_options_sheet.dart';
import '../../widgets/library_picker.dart';

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
/// (класс/характеристика/Сложность спасения/бонус атаки), как на листе персонажа.
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
                const _SpellSlotsCard(),
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
                onPressed: () => showAddOptionsSheet(
                  context,
                  onManual: () => _showSpellDialog(context, characterId: characterId),
                  onFromLibrary: () => _addFromLibrary(context, characterId: characterId),
                ),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _addFromLibrary(BuildContext context, {required int characterId}) async {
    final picked = await showLibraryPickerDialog(context, type: LibraryItemType.spell);
    if (picked == null || !context.mounted) return;

    final data = picked.data;
    final spell = SpellModel(
      characterId: characterId,
      name: picked.name,
      level: (data['level'] as num?)?.toInt() ?? 0,
      type: data['school'] as String? ?? '',
      range: data['range'] as String? ?? '',
      components: data['components'] as String? ?? '',
      castingTime: data['castingTime'] as String? ?? '',
      duration: data['duration'] as String? ?? '',
      description: data['description'] as String? ?? '',
      libraryItemId: picked.id,
      sourceUrl: picked.sourceUrl,
    );
    await context.read<SpellProvider>().addSpell(spell);
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
    final sourceUrlController = TextEditingController(text: existing?.sourceUrl ?? '');
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
                const SizedBox(height: 10),
                TextField(
                  controller: sourceUrlController,
                  decoration: const InputDecoration(labelText: 'Ссылка на источник (необязательно)'),
                  keyboardType: TextInputType.url,
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
      sourceUrl: sourceUrlController.text.trim(),
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
/// атаки заклинанием — верхний блок страницы заклинаний на листе персонажа.
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

/// Компактный блок ячеек заклинаний: показываются только уровни с положительным
/// максимумом; настройка максимума вынесена в отдельный диалог.
class _SpellSlotsCard extends StatelessWidget {
  const _SpellSlotsCard();

  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    return Consumer<SpellSlotProvider>(
      builder: (context, provider, _) {
        final levels = [
          for (int level = 1; level <= 9; level++)
            if (provider.slotFor(level).total > 0) level,
        ];

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Ячейки заклинаний',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                  if (levels.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.tune, size: 20),
                      tooltip: 'Настроить количество ячеек',
                      color: AppTheme.textSecondary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 40, height: 36),
                      onPressed: () => _configure(context, provider),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (levels.isEmpty)
                _buildEmpty(context, provider)
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 720
                        ? 3
                        : constraints.maxWidth >= 460
                            ? 2
                            : 1;
                    return Column(
                      children: [
                        for (int i = 0; i < levels.length; i += columns) ...[
                          if (i > 0) const SizedBox(height: _gap),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (int c = 0; c < columns; c++) ...[
                                if (c > 0) const SizedBox(width: _gap),
                                Expanded(
                                  child: i + c < levels.length
                                      ? _SlotRow(
                                          level: levels[i + c],
                                          slot: provider.slotFor(levels[i + c]),
                                          onAdjust: (delta) =>
                                              provider.adjustUsed(levels[i + c], delta),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context, SpellSlotProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Ячейки заклинаний ещё не настроены. Укажите, сколько ячеек каждого уровня есть у персонажа.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => _configure(context, provider),
          icon: const Icon(Icons.tune),
          label: const Text('Настроить ячейки'),
        ),
      ],
    );
  }

  /// Диалог настройки максимального количества ячеек по уровням 1–9.
  static Future<void> _configure(BuildContext context, SpellSlotProvider provider) async {
    final totals = <int, int>{
      for (int level = 1; level <= 9; level++) level: provider.slotFor(level).total,
    };

    final result = await showDialog<Map<int, int>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Ячейки заклинаний'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Максимум ячеек по уровням. Уровни с нулём не показываются на листе.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  for (int level = 1; level <= 9; level++)
                    Row(
                      children: [
                        Expanded(child: Text('Уровень $level')),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: totals[level]! > 0
                              ? () => setState(() => totals[level] = totals[level]! - 1)
                              : null,
                        ),
                        SizedBox(
                          width: 32,
                          child: Text('${totals[level]}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: totals[level]! < 99
                              ? () => setState(() => totals[level] = totals[level]! + 1)
                              : null,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(Map<int, int>.of(totals)),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;

    for (final entry in result.entries) {
      if (provider.slotFor(entry.key).total == entry.value) continue;
      await provider.setTotal(entry.key, entry.value);
      // Если максимум стал меньше потраченных — подтягиваем потраченные к максимуму.
      if (provider.slotFor(entry.key).used > entry.value) {
        await provider.adjustUsed(entry.key, 0);
      }
    }
  }
}

/// Один уровень: метка, индикаторы (заполненные — доступные, пустые — потраченные),
/// счётчик «потрачено/всего» и кнопки изменения количества потраченных ячеек.
class _SlotRow extends StatelessWidget {
  final int level;
  final SpellSlotModel slot;
  final ValueChanged<int> onAdjust;

  const _SlotRow({required this.level, required this.slot, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final used = slot.used.clamp(0, slot.total).toInt();
    final available = slot.total - used;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text('Ур. $level',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (int i = 0; i < slot.total; i++)
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < available ? AppTheme.accent : Colors.transparent,
                      border: Border.all(
                        color: i < available
                            ? AppTheme.accent
                            : AppTheme.textSecondary.withOpacity(0.6),
                        width: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$used/${slot.total}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const Text('потрачено',
                  style: TextStyle(fontSize: 9, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(width: 2),
          IconButton(
            icon: const Icon(Icons.remove, size: 20, color: AppTheme.accent),
            tooltip: 'Вернуть ячейку',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            onPressed: used > 0 ? () => onAdjust(-1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 20, color: AppTheme.accent),
            tooltip: 'Потратить ячейку',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            onPressed: used < slot.total ? () => onAdjust(1) : null,
          ),
        ],
      ),
    );
  }
}

/// Строка заклинания: название и основные параметры в свёрнутом виде,
/// полные параметры и описание — по нажатию. Редактирование — отдельной кнопкой.
class _SpellTile extends StatefulWidget {
  final SpellModel spell;
  final int characterId;

  const _SpellTile({super.key, required this.spell, required this.characterId});

  @override
  State<_SpellTile> createState() => _SpellTileState();
}

class _SpellTileState extends State<_SpellTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final spell = widget.spell;
    final summary = [
      if (spell.type.isNotEmpty) spell.type,
      if (spell.range.isNotEmpty) spell.range,
      if (spell.castingTime.isNotEmpty) spell.castingTime,
      if (spell.components.isNotEmpty) _localizedComponents(spell.components),
    ].join(' · ');

    final params = <(String, String)>[
      if (spell.type.isNotEmpty) ('Школа', spell.type),
      if (spell.castingTime.isNotEmpty) ('Время накладывания', spell.castingTime),
      if (spell.range.isNotEmpty) ('Дальность', spell.range),
      if (spell.duration.isNotEmpty) ('Длительность', spell.duration),
      if (spell.components.isNotEmpty)
        ('Компоненты', _localizedComponents(spell.components)),
      ('Подготовлено', spell.prepared ? 'Да' : 'Нет'),
    ];

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  spell.prepared ? Icons.auto_fix_high : Icons.auto_fix_normal_outlined,
                  color: spell.prepared ? AppTheme.accent : AppTheme.textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(spell.name,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      if (summary.isNotEmpty)
                        Text(
                          summary,
                          maxLines: _expanded ? null : 2,
                          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 22),
                  tooltip: 'Редактировать',
                  color: AppTheme.textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                  onPressed: () => _SpellsSectionState._showSpellDialog(
                    context,
                    characterId: widget.characterId,
                    existing: spell,
                  ),
                ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 22,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(38, 10, 10, 4),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 20,
                              runSpacing: 8,
                              children: [
                                for (final (label, value) in params)
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(minWidth: 90, maxWidth: 320),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(label,
                                            style: const TextStyle(
                                                fontSize: 11, color: AppTheme.textSecondary)),
                                        Text(value, style: const TextStyle(fontSize: 13)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              spell.description.isEmpty
                                  ? 'Описание отсутствует.'
                                  : spell.description,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: spell.description.isEmpty
                                    ? AppTheme.textSecondary
                                    : AppTheme.textPrimary,
                              ),
                            ),
                            if (spell.sourceUrl.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text('Источник: ${spell.sourceUrl}',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppTheme.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
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
                  _SpellTile(
                    key: ValueKey(spells[i].id ?? spells[i].syncId),
                    spell: spells[i],
                    characterId: characterId,
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
