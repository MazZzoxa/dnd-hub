import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/constants/dnd_data.dart';
import '../../../data/models/attack_model.dart';
import '../../../data/models/character_model.dart';
import '../../../domain/providers/attack_provider.dart';
import '../../../domain/providers/character_provider.dart';
import '../../widgets/quick_adjust_card.dart';
import '../../widgets/stat_box.dart';

/// Главный экран персонажа: соответствует первой странице листа Aternia —
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
      });
    }

    return Consumer<CharacterProvider>(
      builder: (context, provider, _) {
        final character = provider.selected;
        if (character == null) {
          return const Center(child: Text('Персонаж не выбран'));
        }
        final perceptionSkill =
            kSkills.firstWhere((s) => s.key == kPerceptionSkillKey);
        final perceptionMod = character.skillMod(perceptionSkill.key, perceptionSkill.ability);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeaderCard(character: character),
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
              valueText:
                  '${character.hp} / ${character.maxHp}${character.temporaryHp > 0 ? '  (+${character.temporaryHp} temp)' : ''}',
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
            if (character.hp == 0) ...[
              const SizedBox(height: 10),
              _DeathSavesCard(character: character, provider: provider),
            ],
            const SizedBox(height: 10),
            QuickAdjustCard(
              label: 'Золото (ЗМ)',
              icon: Icons.monetization_on,
              accentColor: Colors.amber,
              valueText: '${character.gold}',
              step: 1,
              onAdjust: (delta) => provider.adjustGold(delta),
              onTapValue: () => _showAdjustDialog(
                context,
                title: 'Изменить золото',
                initial: character.gold,
                onSubmit: (value) =>
                    provider.updateCharacter(character.copyWith(gold: value)),
              ),
            ),
            const SizedBox(height: 10),
            QuickAdjustCard(
              label: 'Опыт',
              icon: Icons.star,
              accentColor: AppTheme.accent,
              valueText: '${character.xp}',
              step: 10,
              onAdjust: (delta) => provider.adjustXp(delta),
              onTapValue: () => _showAdjustDialog(
                context,
                title: 'Изменить опыт',
                initial: character.xp,
                onSubmit: (value) =>
                    provider.updateCharacter(character.copyWith(xp: value)),
              ),
            ),
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
            const SizedBox(height: 20),
            const _SectionLabel('Прочее'),
            const SizedBox(height: 10),
            _CurrencyRow(character: character),
          ],
        );
      },
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
          decoration: const InputDecoration(labelText: 'напр. 20к10'),
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
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primary.withOpacity(0.2),
            child: Text(
              character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 22),
            ),
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

class _AttributesGrid extends StatelessWidget {
  final CharacterModel character;
  const _AttributesGrid({required this.character});

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
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.3,
      children: attrs.map((a) {
        final (label, score, mod) = a;
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('$score', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(mod >= 0 ? '+$mod' : '$mod',
                  style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
            ],
          ),
        );
      }).toList(),
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

class _CurrencyRow extends StatelessWidget {
  final CharacterModel character;
  const _CurrencyRow({required this.character});

  @override
  Widget build(BuildContext context) {
    Widget coin(String label, int value) => Expanded(
          child: Column(
            children: [
              Text('$value', style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          coin('ММ', character.copper),
          coin('СМ', character.silver),
          coin('ЭМ', character.electrum),
          coin('ЗМ', character.gold),
          coin('ПМ', character.platinum),
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
