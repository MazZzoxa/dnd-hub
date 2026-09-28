import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/battle_projection_model.dart';
import '../../data/models/character_model.dart';

class BattleCharacterCard extends StatelessWidget {
  final String name;
  final int hp;
  final int maxHp;
  final int temporaryHp;
  final int armorClass;
  final int initiative;
  final bool canEdit;
  final VoidCallback? onTap;
  final VoidCallback? onDamage;
  final VoidCallback? onHeal;
  final VoidCallback? onTemporaryHp;

  const BattleCharacterCard({
    super.key,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.temporaryHp,
    required this.armorClass,
    this.initiative = 0,
    required this.canEdit,
    this.onTap,
    this.onDamage,
    this.onHeal,
    this.onTemporaryHp,
  });

  factory BattleCharacterCard.fromCharacter({
    Key? key,
    required CharacterModel character,
    required bool canEdit,
    VoidCallback? onTap,
    VoidCallback? onDamage,
    VoidCallback? onHeal,
    VoidCallback? onTemporaryHp,
  }) =>
      BattleCharacterCard(
        key: key,
        name: character.name,
        hp: character.hp,
        maxHp: character.maxHp,
        temporaryHp: character.temporaryHp,
        armorClass: character.armorClass,
        initiative: character.initiative,
        canEdit: canEdit,
        onTap: onTap,
        onDamage: onDamage,
        onHeal: onHeal,
        onTemporaryHp: onTemporaryHp,
      );

  factory BattleCharacterCard.fromProjection({
    Key? key,
    required BattleProjectionModel projection,
    required bool canEdit,
    VoidCallback? onTap,
    VoidCallback? onDamage,
    VoidCallback? onHeal,
    VoidCallback? onTemporaryHp,
  }) =>
      BattleCharacterCard(
        key: key,
        name: projection.name,
        hp: projection.hp,
        maxHp: projection.maxHp,
        temporaryHp: projection.temporaryHp,
        armorClass: projection.armorClass,
        initiative: projection.initiative,
        canEdit: canEdit,
        onTap: onTap,
        onDamage: onDamage,
        onHeal: onHeal,
        onTemporaryHp: onTemporaryHp,
      );

  @override
  Widget build(BuildContext context) {
    final safeMax = maxHp <= 0 ? 1 : maxHp;
    final hpRatio = (hp / safeMax).clamp(0.0, 1.0);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  child: Icon(Icons.person_outline),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'КД $armorClass',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Иниц. ${initiative >= 0 ? '+' : ''}$initiative',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text('Хиты'),
                const Spacer(),
                Text(
                  '$hp / $maxHp',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: hpRatio,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                const Text(
                  'Временные хиты',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                const Spacer(),
                Text(
                  '$temporaryHp',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (canEdit) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: onDamage,
                    icon: const Icon(Icons.favorite_border),
                    label: const Text('Урон'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onHeal,
                    icon: const Icon(Icons.favorite),
                    label: const Text('Лечение'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onTemporaryHp,
                    icon: const Icon(Icons.shield_outlined),
                    label: const Text('Врем. хиты'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}
