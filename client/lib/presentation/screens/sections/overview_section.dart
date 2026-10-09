import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../widgets/character_avatar.dart';
import '../../../data/constants/dnd_data.dart';
import '../../../data/models/attack_model.dart';
import '../../../data/models/character_model.dart';
import '../../../data/models/character_condition_model.dart';
import '../../../domain/providers/attack_provider.dart';
import '../../../domain/providers/character_provider.dart';
import '../../../domain/providers/xp_provider.dart';
import '../../../domain/providers/gameplay_state_provider.dart';
import '../../../domain/xp/xp_service.dart';
import '../../widgets/xp_progress_card.dart';
import '../../widgets/xp_history_sheet.dart';
import '../../widgets/character_campaigns_card.dart';
import '../../widgets/quick_adjust_card.dart';
import '../../widgets/stat_box.dart';

/// Главный экран персонажа: соответствует первой странице листа персонажа —
/// HP / AC / Initiative / вдохновение / спасброски / навыки / атаки и т.д.
/// Всё, что нужно "во время сессии", собрано на одном скроллящемся экране.
class OverviewSection extends StatefulWidget {
  const OverviewSection({super.key});

  @override
  State<OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<OverviewSection> {
  int? _loadedForCharacterId;

  @override
  Widget build(BuildContext context) {
    final characterId = context.watch<CharacterProvider>().selected?.id;
    if (characterId != null && _loadedForCharacterId != characterId) {
      _loadedForCharacterId = characterId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<AttackProvider>().loadForCharacter(characterId);
        final selected = context.read<CharacterProvider>().selected;
        if (selected?.id == characterId && selected != null) {
          context.read<GameplayStateProvider>().loadCharacter(characterId, selected.syncId);
        }
      });
    }

    return Consumer<CharacterProvider>(
      builder: (context, provider, _) {
        final character = provider.selected;
        if (character == null) {
          return const Center(child: Text('Персонаж не выбран'));
        }
        final gameplay = context.watch<GameplayStateProvider>();
        final conditions = gameplay.conditionsFor(character.syncId);
        final perceptionSkill =
            kSkills.firstWhere((s) => s.key == kPerceptionSkillKey);
        final perceptionMod = character.skillMod(perceptionSkill.key, perceptionSkill.ability);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(character: character),
            const SizedBox(height: 10),
            CharacterCampaignsCard(characterId: character.id!),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InspirationBox(
                    active: character.inspiration,
                    onTap: () => provider.toggleInspiration(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatBox(
                    label: 'Бонус мастерства',
                    value: '+${character.proficiencyBonus}',
                    icon: Icons.workspace_premium,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HitDiceBox(
                    value: character.hitDice,
                    onTap: () => _editHitDice(context, character),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: StatBox(
                    label: 'КД',
                    value: '${character.armorClass}',
                    icon: Icons.shield,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatBox(
                    label: 'Инициатива',
                    value: character.initiative >= 0
                        ? '+${character.initiative}'
                        : '${character.initiative}',
                    icon: Icons.bolt,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: StatBox(
                    label: 'Скорость',
                    value: '${character.speed} фут.',
                    icon: Icons.directions_run,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            QuickAdjustCard(
              label: 'Хиты',
              icon: Icons.favorite,
              accentColor: AppTheme.danger,
              valueText: '${character.hp} / ${character.maxHp}',
              step: 1,
              onAdjust: (delta) => provider.adjustHp(delta),
              onTapValue: () => _showAdjustDialog(
                context,
                title: 'Изменить хиты',
                initial: character.hp,
                onSubmit: (value) =>
                    provider.updateCharacter(character.copyWith(hp: value)),
              ),
            ),
            const SizedBox(height: 10),
            QuickAdjustCard(
              label: 'Временные хиты',
              icon: Icons.shield_outlined,
              accentColor: AppTheme.primary,
              valueText: '${character.temporaryHp}',
              step: 1,
              onAdjust: (delta) => provider.setTemporaryHp(
                character.temporaryHp + delta,
              ),
              onTapValue: () => _showAdjustDialog(
                context,
                title: 'Изменить временные хиты',
                initial: character.temporaryHp,
                onSubmit: provider.setTemporaryHp,
              ),
            ),
            if (character.lifeState != CharacterLifeState.normal || conditions.isNotEmpty) ...[
              const SizedBox(height: 10),
              _GameplayStateCard(
                character: character,
                conditions: conditions,
                onConditionTap: (condition) => _showConditionDetails(context, condition),
              ),
            ],
            if (character.lifeState == CharacterLifeState.downed) ...[
              const SizedBox(height: 10),
              _DeathSavesCard(character: character, provider: provider),
            ],
            const SizedBox(height: 10),
            _WalletCard(character: character, provider: provider),
            const SizedBox(height: 10),
            Builder(builder: (context) {
              final progress = XpService().progress(character);
              final xpProvider = context.watch<XpProvider>();
              if (!xpProvider.loading && xpProvider.history.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) => xpProvider.loadHistory(character.id!));
              }
              return Column(children: [
                XpProgressCard(
                  progress: progress,
                  onHistory: () async {
                    await xpProvider.loadHistory(character.id!);
                    if (!context.mounted) return;
                    await showXpHistorySheet(context, xpProvider.history);
                  },
                ),
                const SizedBox(height: 10),
                QuickAdjustCard(
                  label: 'Опыт',
                  icon: Icons.star,
                  accentColor: AppTheme.accent,
                  valueText: '${character.xp}',
                  step: 10,
                  onAdjust: (delta) async {
                    await provider.adjustXp(delta);
                    await xpProvider.refresh();
                  },
                  onTapValue: () async {
                    final controller = TextEditingController(text: '${character.xp}');
                    final reason = TextEditingController();
                    final result = await showDialog<(int, String)?>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Изменить опыт'),
                        content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
                          TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Новый опыт')),
                          const SizedBox(height: 12),
                          TextField(controller: reason, maxLines: 2, decoration: const InputDecoration(labelText: 'Причина (необязательно)')),
                        ])),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
                          FilledButton(onPressed: () { final value = int.tryParse(controller.text); if (value != null && value >= 0) Navigator.pop(context, (value, reason.text)); }, child: const Text('Сохранить')),
                        ],
                      ),
                    );
                    controller.dispose();
                    reason.dispose();
                    if (result == null) return;
                    await provider.adjustXp(result.$1 - character.xp, reason: result.$2);
                    await xpProvider.refresh();
                  },
                ),
              ]);
            }),
            const SizedBox(height: 20),
            const _SectionLabel('Характеристики'),
            const SizedBox(height: 10),
            _AttributesGrid(character: character),
            const SizedBox(height: 20),
            const _SectionLabel('Спасброски'),
            const SizedBox(height: 10),
            _SavingThrowsCard(character: character, provider: provider),
            const SizedBox(height: 20),
            Row(
              children: [
                const _SectionLabel('Навыки'),
                const Spacer(),
                Text('Пасс. Внимательность: ${character.passivePerception(perceptionMod)}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            _SkillsCard(character: character, provider: provider),
            const SizedBox(height: 20),
            const _SectionLabel('Атаки и заклинания'),
            const SizedBox(height: 10),
            _AttacksCard(characterId: character.id!),
          ],
        );
      },
    );
  }

  Future<void> _showConditionDetails(
    BuildContext context,
    CharacterConditionModel condition,
  ) async {
    final source = condition.sourceLabel.isNotEmpty ? condition.sourceLabel : condition.sourceCharacterSyncId;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(condition.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (source.isNotEmpty) Text('Источник: $source'),
            if (source.isNotEmpty) const SizedBox(height: 8),
            if (condition.durationRounds > 0) Text('Осталось: ${condition.remainingRounds} раунд${condition.remainingRounds == 1 ? '' : 'а'}'),
            if (condition.durationRounds > 0) const SizedBox(height: 8),
            Text(condition.description.isEmpty ? 'Описание отсутствует.' : condition.description),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _editHitDice(BuildContext context, CharacterModel character) async {
    final controller = TextEditingController(text: character.hitDice);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Кость хитов'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'напр. 1к10'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result != null && context.mounted) {
      await context
          .read<CharacterProvider>()
          .updateCharacter(character.copyWith(hitDice: result));
    }
  }

  Future<void> _showAdjustDialog(
    BuildContext context, {
    required String title,
    required int initial,
    required Future<void> Function(int value) onSubmit,
  }) async {
    final controller = TextEditingController(text: '$initial');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Значение'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              Navigator.of(context).pop(value);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (result != null) {
      await onSubmit(result);
    }
  }
}

class _HeaderCard extends StatelessWidget {
  final CharacterModel character;
  const _HeaderCard({required this.character});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CharacterAvatar(
            character: character,
            radius: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(character.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  '${character.race} · ${character.className}'
                  '${character.subclass.isNotEmpty ? ' (${character.subclass})' : ''} · Ур. ${character.level}',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                if (character.alignment.isNotEmpty || character.background.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (character.background.isNotEmpty) character.background,
                      if (character.alignment.isNotEmpty) character.alignment,
                    ].join(' · '),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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

class _InspirationBox extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const _InspirationBox({required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(0.25) : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                color: active ? AppTheme.primary : AppTheme.accent, size: 20),
            const SizedBox(height: 6),
            Text(active ? 'Есть' : 'Нет',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text('Вдохновение',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _HitDiceBox extends StatelessWidget {
  final String value;
  final VoidCallback onTap;
  const _HitDiceBox({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.casino, color: AppTheme.accent, size: 20),
            const SizedBox(height: 6),
            Text(value.isEmpty ? '—' : value,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            const Text('Кость хитов',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _GameplayStateCard extends StatelessWidget {
  final CharacterModel character;
  final List<CharacterConditionModel> conditions;
  final ValueChanged<CharacterConditionModel> onConditionTap;

  const _GameplayStateCard({
    required this.character,
    required this.conditions,
    required this.onConditionTap,
  });

  @override
  Widget build(BuildContext context) {
    // Пока персонаж жив и у него нет активных условий, игровой статус
    // не занимает место на листе. Это также убирает длинный
    // "Нормальное состояние" Chip с узких экранов Android.
    final hasLifeState = character.lifeState != CharacterLifeState.normal;
    if (!hasLifeState && conditions.isEmpty) {
      return const SizedBox.shrink();
    }

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
              const Icon(Icons.health_and_safety_outlined, size: 19),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Игровое состояние',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (hasLifeState) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Chip(
                    label: Text(character.lifeState.label),
                  ),
                ),
              ],
            ],
          ),
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Состояния',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final condition in conditions)
                  ActionChip(
                    label: Text(condition.name),
                    onPressed: () => onConditionTap(condition),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'Активных состояний нет.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeathSavesCard extends StatelessWidget {
  final CharacterModel character;
  final CharacterProvider provider;
  const _DeathSavesCard({required this.character, required this.provider});

  @override
  Widget build(BuildContext context) {
    Widget dots(String label, int count, Color color, ValueChanged<int> onSet) {
      return Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final filled = i < count;
              return GestureDetector(
                onTap: () => onSet(filled && i == count - 1 ? count - 1 : i + 1),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled ? color : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                  ),
                ),
              );
            }),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          dots('Успехи', character.deathSaveSuccesses, AppTheme.success,
              provider.setDeathSaveSuccesses),
          dots('Провалы', character.deathSaveFailures, AppTheme.danger,
              provider.setDeathSaveFailures),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textSecondary),
            onPressed: provider.resetDeathSaves,
            tooltip: 'Сбросить',
          ),
        ],
      ),
    );
  }
}

/// Характеристики: на узких экранах сетка 3 × 2, на широких — одна строка из шести.
class _AttributesGrid extends StatelessWidget {
  final CharacterModel character;
  const _AttributesGrid({required this.character});

  static const double _wideBreakpoint = 560;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final attrs = [
      ('СИЛ', character.strength, character.strengthMod),
      ('ЛОВ', character.dexterity, character.dexterityMod),
      ('ТЕЛ', character.constitution, character.constitutionMod),
      ('ИНТ', character.intelligence, character.intelligenceMod),
      ('МДР', character.wisdom, character.wisdomMod),
      ('ХАР', character.charisma, character.charismaMod),
    ];
    final cards = [
      for (final (label, score, mod) in attrs)
        _AttributeCard(label: label, score: score, mod: mod),
    ];

    // Без CrossAxisAlignment.stretch: экран лежит в ListView с неограниченной
    // высотой, stretch в таком Row приводит к бесконечным ограничениям.
    Widget row(List<Widget> items) => Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              Expanded(child: items[i]),
            ],
          ],
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _wideBreakpoint) {
          return row(cards);
        }
        return Column(
          children: [
            row(cards.sublist(0, 3)),
            const SizedBox(height: _gap),
            row(cards.sublist(3, 6)),
          ],
        );
      },
    );
  }
}

class _AttributeCard extends StatelessWidget {
  final String label;
  final int score;
  final int mod;
  const _AttributeCard({required this.label, required this.score, required this.mod});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11, letterSpacing: 0.3)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$score',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, height: 1.15)),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(mod >= 0 ? '+$mod' : '$mod',
                style: const TextStyle(
                    color: AppTheme.accent, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _SavingThrowsCard extends StatelessWidget {
  final CharacterModel character;
  final CharacterProvider provider;
  const _SavingThrowsCard({required this.character, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (int i = 0; i < kAbilities.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _ProficiencyRow(
              label: kAbilities[i].fullLabel,
              proficient: character.savingThrowProficiencies.contains(kAbilities[i].key),
              modifier: character.savingThrowMod(kAbilities[i].key),
              onTap: () => provider.toggleSavingThrowProficiency(kAbilities[i].key),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkillsCard extends StatelessWidget {
  final CharacterModel character;
  final CharacterProvider provider;
  const _SkillsCard({required this.character, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (int i = 0; i < kSkills.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            _ProficiencyRow(
              label: kSkills[i].label,
              sublabel: kAbilities
                  .firstWhere((a) => a.key == kSkills[i].ability)
                  .shortLabel,
              proficient: character.skillProficiencies.contains(kSkills[i].key),
              modifier: character.skillMod(kSkills[i].key, kSkills[i].ability),
              onTap: () => provider.toggleSkillProficiency(kSkills[i].key),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProficiencyRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool proficient;
  final int modifier;
  final VoidCallback onTap;

  const _ProficiencyRow({
    required this.label,
    required this.proficient,
    required this.modifier,
    required this.onTap,
    this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              proficient ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: proficient ? AppTheme.primary : AppTheme.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                sublabel != null ? '$label ($sublabel)' : label,
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Text(
              modifier >= 0 ? '+$modifier' : '$modifier',
              style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttacksCard extends StatelessWidget {
  final int characterId;
  const _AttacksCard({required this.characterId});

  @override
  Widget build(BuildContext context) {
    return Consumer<AttackProvider>(
      builder: (context, provider, _) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (int i = 0; i < provider.attacks.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  onTap: () => _showAttackDialog(
                    context,
                    characterId: characterId,
                    existing: provider.attacks[i],
                  ),
                  title: Text(provider.attacks[i].name),
                  subtitle: Text(provider.attacks[i].damage),
                  trailing: Text(
                    provider.attacks[i].attackBonus,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.accent),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton.icon(
                  onPressed: () => _showAttackDialog(context, characterId: characterId),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить атаку'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAttackDialog(
    BuildContext context, {
    required int characterId,
    AttackModel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final bonusController = TextEditingController(text: existing?.attackBonus ?? '');
    final damageController = TextEditingController(text: existing?.damage ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Новая атака' : 'Изменить атаку'),
        content: Column(
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
                  controller: bonusController,
                  decoration: const InputDecoration(labelText: 'Бонус атаки'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: damageController,
                  decoration: const InputDecoration(labelText: 'Урон/вид'),
                ),
              ),
            ]),
          ],
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () {
                context.read<AttackProvider>().deleteAttack(existing.id!);
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
    );

    if (saved != true || !context.mounted) return;
    if (nameController.text.trim().isEmpty) return;

    final attack = AttackModel(
      id: existing?.id,
      characterId: characterId,
      name: nameController.text.trim(),
      attackBonus: bonusController.text.trim(),
      damage: damageController.text.trim(),
    );

    final provider = context.read<AttackProvider>();
    if (existing == null) {
      await provider.addAttack(attack);
    } else {
      await provider.updateAttack(attack);
    }
  }
}

/// Описание одного номинала монет.
class _Coin {
  final String key;
  final String abbr;
  final String name;
  final Color color;
  const _Coin(this.key, this.abbr, this.name, this.color);
}

const _coins = <_Coin>[
  _Coin('copper', 'ММ', 'Медные', Color(0xFFD08A5A)),
  _Coin('silver', 'СМ', 'Серебряные', Color(0xFFB0BEC5)),
  _Coin('electrum', 'ЭМ', 'Электрумовые', Color(0xFF6FCFB8)),
  _Coin('gold', 'ЗМ', 'Золотые', Color(0xFFFFC107)),
  _Coin('platinum', 'ПМ', 'Платиновые', Color(0xFFB39DDB)),
];

int _coinValue(CharacterModel c, String key) {
  switch (key) {
    case 'copper':
      return c.copper;
    case 'silver':
      return c.silver;
    case 'electrum':
      return c.electrum;
    case 'gold':
      return c.gold;
    case 'platinum':
      return c.platinum;
  }
  return 0;
}

CharacterModel _withCoin(CharacterModel c, String key, int value) {
  switch (key) {
    case 'copper':
      return c.copyWith(copper: value);
    case 'silver':
      return c.copyWith(silver: value);
    case 'electrum':
      return c.copyWith(electrum: value);
    case 'gold':
      return c.copyWith(gold: value);
    case 'platinum':
      return c.copyWith(platinum: value);
  }
  return c;
}

/// Единый «Кошелёк»: все пять номиналов одновременно, включая нулевые.
/// Данные и синхронизация идут через прежний `CharacterProvider.updateCharacter`.
class _WalletCard extends StatelessWidget {
  final CharacterModel character;
  final CharacterProvider provider;
  const _WalletCard({required this.character, required this.provider});

  static const double _wideBreakpoint = 600;
  static const double _gap = 8;

  Future<void> _setCoin(String key, int value) async {
    final current = provider.selected;
    if (current == null) return;
    final next = value.clamp(0, 1 << 30).toInt();
    await provider.updateCharacter(_withCoin(current, key, next));
  }

  Future<void> _adjustCoin(String key, int delta) async {
    // Берём актуальное значение в момент нажатия, чтобы быстрые тапы не терялись.
    final current = provider.selected;
    if (current == null) return;
    await _setCoin(key, _coinValue(current, key) + delta);
  }

  Future<void> _editCoin(BuildContext context, _Coin coin) async {
    final current = _coinValue(character, coin.key);
    final controller = TextEditingController(text: '$current');
    var mode = 0; // 0 — задать, 1 — добавить, 2 — вычесть

    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          int? computeResult() {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 0) return null;
            switch (mode) {
              case 1:
                return (current + v).clamp(0, 1 << 30).toInt();
              case 2:
                return (current - v).clamp(0, 1 << 30).toInt();
              default:
                return v;
            }
          }

          final preview = computeResult();
          void apply() {
            final value = computeResult();
            if (value != null) Navigator.of(dialogContext).pop(value);
          }

          Widget modeChip(int value, String label) => ChoiceChip(
                label: Text(label),
                selected: mode == value,
                onSelected: (_) => setState(() {
                  mode = value;
                  controller.text = value == 0 ? '$current' : '';
                  controller.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: controller.text.length,
                  );
                }),
              );

          return AlertDialog(
            title: Text('${coin.name} монеты (${coin.abbr})'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Сейчас: $current',
                      style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      modeChip(0, 'Задать'),
                      modeChip(1, 'Добавить'),
                      modeChip(2, 'Вычесть'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => apply(),
                    decoration: InputDecoration(
                      labelText: mode == 0 ? 'Новое значение' : 'Количество монет',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    preview == null ? 'Введите целое число от 0' : 'Станет: $preview ${coin.abbr}',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: preview == null ? null : apply,
                child: const Text('Применить'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null) {
      await _setCoin(coin.key, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, size: 20, color: Colors.amber),
              SizedBox(width: 8),
              Text('Кошелёк', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _wideBreakpoint;
              final tiles = [
                for (final coin in _coins)
                  _CoinTile(
                    coin: coin,
                    value: _coinValue(character, coin.key),
                    vertical: wide,
                    onAdjust: (delta) => _adjustCoin(coin.key, delta),
                    onEdit: () => _editCoin(context, coin),
                  ),
              ];
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                );
              }
              // Узкий экран: два столбца, последний (пятый) номинал — на всю ширину.
              return Column(
                children: [
                  for (int i = 0; i < tiles.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: _gap),
                    Row(
                      children: [
                        Expanded(child: tiles[i]),
                        if (i + 1 < tiles.length) ...[
                          const SizedBox(width: _gap),
                          Expanded(child: tiles[i + 1]),
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
  }
}

class _CoinTile extends StatelessWidget {
  final _Coin coin;
  final int value;
  final bool vertical;
  final ValueChanged<int> onAdjust;
  final VoidCallback onEdit;

  const _CoinTile({
    required this.coin,
    required this.value,
    required this.vertical,
    required this.onAdjust,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: coin.color.withOpacity(0.10),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: coin.color.withOpacity(0.35)),
    );

    final valueText = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: vertical ? Alignment.center : Alignment.centerLeft,
      child: Text(
        '$value',
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: AppTheme.textPrimary,
        ),
      ),
    );

    if (vertical) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: decoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _CoinBadge(coin: coin),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    coin.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ),
              ],
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: SizedBox(width: double.infinity, child: valueText),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _CoinButton(
                    icon: Icons.remove,
                    color: coin.color,
                    tooltip: '−1 ${coin.abbr} (удержание: −5)',
                    onTap: () => onAdjust(-1),
                    onLongPress: () => onAdjust(-5),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _CoinButton(
                    icon: Icons.add,
                    color: coin.color,
                    tooltip: '+1 ${coin.abbr} (удержание: +5)',
                    onTap: () => onAdjust(1),
                    onLongPress: () => onAdjust(5),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: decoration,
      child: Row(
        children: [
          Tooltip(message: coin.name, child: _CoinBadge(coin: coin)),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: valueText,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _CoinButton(
            icon: Icons.remove,
            color: coin.color,
            tooltip: '−1 ${coin.abbr} (удержание: −5)',
            width: 34,
            onTap: () => onAdjust(-1),
            onLongPress: () => onAdjust(-5),
          ),
          const SizedBox(width: 4),
          _CoinButton(
            icon: Icons.add,
            color: coin.color,
            tooltip: '+1 ${coin.abbr} (удержание: +5)',
            width: 34,
            onTap: () => onAdjust(1),
            onLongPress: () => onAdjust(5),
          ),
        ],
      ),
    );
  }
}

class _CoinBadge extends StatelessWidget {
  final _Coin coin;
  const _CoinBadge({required this.coin});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: coin.color.withOpacity(0.25),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        coin.abbr,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: coin.color),
      ),
    );
  }
}

class _CoinButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final double? width;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CoinButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
    required this.onLongPress,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: SizedBox(
            width: width,
            height: 40,
            child: Icon(icon, color: color, size: 22),
          ),
        ),
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
