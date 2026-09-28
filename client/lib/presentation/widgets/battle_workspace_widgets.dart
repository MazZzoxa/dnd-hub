import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/battle_action_request_model.dart';
import '../../data/models/battle_log_entry_model.dart';
import '../../data/models/character_model.dart';

class BattleCurrentTurnCard extends StatelessWidget {
  final String characterName;
  final int sequence;
  final bool canEnd;
  final VoidCallback? onEnd;

  const BattleCurrentTurnCard({
    super.key,
    required this.characterName,
    required this.sequence,
    required this.canEnd,
    this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.flash_on_outlined, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Текущий ход',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$characterName · #$sequence',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (canEnd)
              FilledButton.tonalIcon(
                onPressed: onEnd,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Завершить ход'),
              ),
          ],
        ),
      ),
    );
  }
}

class BattleActionRequestCard extends StatelessWidget {
  final BattleActionRequestModel request;
  final String actorName;
  final String targetName;
  final VoidCallback? onApprove;
  final VoidCallback? onModify;
  final VoidCallback? onReject;

  const BattleActionRequestCard({
    super.key,
    required this.request,
    required this.actorName,
    required this.targetName,
    this.onApprove,
    this.onModify,
    this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (request.status) {
      BattleActionRequestStatus.declared => 'Объявлено',
      BattleActionRequestStatus.pendingGm => 'Ожидает решения ГМ',
      BattleActionRequestStatus.approved => 'Принято',
      BattleActionRequestStatus.modified => 'Изменено',
      BattleActionRequestStatus.rejected => 'Отклонено',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$actorName — ${request.actionName}',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Chip(label: Text(statusLabel)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Цель: $targetName'),
            if (request.attackTotal != null)
              Text(
                'Попадание: ${request.attackTotal}${request.attackFormula.isEmpty ? '' : ' · ${request.attackFormula}'}',
              ),
            if (request.effectType != BattleEffectType.none &&
                request.effectTotal != null)
              Text(
                '${_effectLabel(request.effectType)}: ${request.effectTotal}${request.effectFormula.isEmpty ? '' : ' · ${request.effectFormula}'}',
              ),
            if (request.resolutionNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                request.resolutionNote,
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
            ],
            if (request.status == BattleActionRequestStatus.pendingGm) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check),
                    label: const Text('Принять'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onModify,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Изменить'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close),
                    label: const Text('Отклонить'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _effectLabel(BattleEffectType effect) => switch (effect) {
        BattleEffectType.none => 'Эффект',
        BattleEffectType.damage => 'Урон',
        BattleEffectType.healing => 'Лечение',
        BattleEffectType.temporaryHp => 'Временные хиты',
      };
}

class BattleJournalList extends StatelessWidget {
  final List<BattleLogEntryModel> entries;
  final String Function(String syncId) characterName;
  final bool gmDetailed;

  const BattleJournalList({
    super.key,
    required this.entries,
    required this.characterName,
    required this.gmDetailed,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Журнал пока пуст.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    final visible = entries.reversed.toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.menu_book_outlined),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Журнал боя',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${entries.length}',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...[
              for (final entry in visible)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _icon(entry.type),
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_text(entry))),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _icon(String type) => switch (type) {
        'turn_started' => '▶',
        'turn_ended' => '■',
        'action_submitted' => '⚡',
        'action_approved' => '✓',
        'action_modified' => '✎',
        'action_rejected' => '✕',
        'attack_roll' => '🎲',
        'damage_roll' => '⚔',
        'healing_roll' => '✚',
        'damage_applied' => '♥',
        'healing_applied' => '＋',
        'temporary_hp_applied' => '▣',
        _ => '•',
      };

  String _text(BattleLogEntryModel entry) {
    final actor = entry.actorCharacterSyncId.isEmpty
        ? ''
        : characterName(entry.actorCharacterSyncId);
    final target = entry.targetLabel.isNotEmpty
        ? entry.targetLabel
        : entry.targetCharacterSyncId.isEmpty
            ? ''
            : characterName(entry.targetCharacterSyncId);
    final amount = entry.amount == null ? '' : ': ${entry.amount}';
    final metadata = entry.metadata;

    switch (entry.type) {
      case 'turn_started':
        return 'Ход №${entry.turnSequence ?? '?'} — $actor';
      case 'turn_ended':
        return 'Ход №${entry.turnSequence ?? '?'} завершён — $actor';
      case 'action_submitted':
        final name = metadata['action_name']?.toString() ?? 'Действие';
        if (gmDetailed) return '$actor → $name → $target';
        return '$actor использовал $name → $target';
      case 'attack_roll':
        final bonus = metadata['bonus']?.toString() ?? '';
        final formula = gmDetailed && metadata['formula'] != null
            ? ' (${metadata['formula']})'
            : '';
        final bonusText = bonus.isEmpty ? '' : ' · бонус атаки $bonus';
        return '$actor: бросок попадания$amount$formula$bonusText';
      case 'damage_roll':
        return '$actor: бросок урона$amount${gmDetailed && metadata['formula'] != null ? ' (${metadata['formula']})' : ''}';
      case 'healing_roll':
        return '$actor: бросок лечения$amount${gmDetailed && metadata['formula'] != null ? ' (${metadata['formula']})' : ''}';
      case 'temporary_hp_applied':
        return '$target получил временные хиты$amount';
      case 'damage_applied':
        if (metadata['hp_before'] != null && metadata['hp_after'] != null) {
          return '$target получил ${entry.amount ?? 0} урона · Хиты ${metadata['hp_before']} → ${metadata['hp_after']}';
        }
        return '$target получил ${entry.amount ?? 0} урона';
      case 'healing_applied':
        if (metadata['hp_before'] != null && metadata['hp_after'] != null) {
          return '$target получил лечение ${entry.amount ?? 0} · Хиты ${metadata['hp_before']} → ${metadata['hp_after']}';
        }
        return '$target получил лечение ${entry.amount ?? 0}';
      case 'action_approved':
        return gmDetailed
            ? '$actor: действие принято ГМ'
            : '$actor: действие принято ГМ';
      case 'action_modified':
        return gmDetailed
            ? '$actor: действие изменено ГМ'
            : '$actor: действие изменено ГМ';
      case 'action_rejected':
        final note = metadata['note']?.toString() ?? '';
        return gmDetailed && note.isNotEmpty
            ? '$actor: действие отклонено — $note'
            : '$actor: действие отклонено ГМ${note.isEmpty ? '' : ' — $note'}';
      default:
        return '${entry.type}${target.isEmpty ? '' : ' → $target'}$amount';
    }
  }
}

String _withLegacyAttackBonus(String formula, Object? rawBonus) {
  final base = formula.trim();
  final bonus = rawBonus?.toString().trim().replaceAll(' ', '') ?? '';
  if (base.isEmpty) return '1к20';
  if (bonus.isEmpty || bonus == '—') return base;
  if (base.contains(RegExp(r'[+\-]\d+$'))) return base;
  if (bonus.startsWith('+') || bonus.startsWith('-')) return '$base$bonus';
  return '$base+$bonus';
}

class BattleActionReviewResult {
  final Map<String, dynamic> modifications;
  final String note;

  const BattleActionReviewResult({
    required this.modifications,
    required this.note,
  });
}

Future<BattleActionReviewResult?> showBattleActionReviewDialog(
  BuildContext context, {
  required BattleActionRequestModel request,
  required List<CharacterModel> allies,
}) async {
  final attackTotal = TextEditingController(
    text: request.attackTotal?.toString() ?? '',
  );
  final attackFormula = TextEditingController(
    text: _withLegacyAttackBonus(request.attackFormula, request.metadata['attack_bonus']),
  );
  final effectTotal = TextEditingController(
    text: request.effectTotal?.toString() ?? '',
  );
  final effectFormula = TextEditingController(text: request.effectFormula);
  final externalTarget = TextEditingController(text: request.targetLabel);
  final note = TextEditingController(text: request.resolutionNote);

  var targetType = request.targetType;
  var effectType = request.effectType;
  var allySyncId = request.targetCharacterSyncId;
  if (allySyncId.isEmpty && allies.isNotEmpty) allySyncId = allies.first.syncId;

  final result = await showDialog<BattleActionReviewResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: Text('Изменить · ${request.actionName}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<BattleTargetType>(
                    value: targetType,
                    decoration: const InputDecoration(labelText: 'Цель'),
                    items: const [
                      DropdownMenuItem(
                        value: BattleTargetType.self,
                        child: Text('Себя'),
                      ),
                      DropdownMenuItem(
                        value: BattleTargetType.ally,
                        child: Text('Союзник'),
                      ),
                      DropdownMenuItem(
                        value: BattleTargetType.external,
                        child: Text('Внешняя цель'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => targetType = value);
                    },
                  ),
                  if (targetType == BattleTargetType.ally) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: allySyncId.isEmpty ? null : allySyncId,
                      decoration: const InputDecoration(labelText: 'Союзник'),
                      items: [
                        for (final character in allies)
                          DropdownMenuItem(
                            value: character.syncId,
                            child: Text(character.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => allySyncId = value ?? ''),
                    ),
                  ],
                  if (targetType == BattleTargetType.external) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: externalTarget,
                      decoration: const InputDecoration(labelText: 'Внешняя цель'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Text('Попадание', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: attackFormula,
                    decoration: const InputDecoration(labelText: 'Формула попадания'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: attackTotal,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Результат попадания'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Урон и эффект', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<BattleEffectType>(
                    value: effectType,
                    decoration: const InputDecoration(labelText: 'Эффект'),
                    items: const [
                      DropdownMenuItem(value: BattleEffectType.none, child: Text('Без эффекта')),
                      DropdownMenuItem(value: BattleEffectType.damage, child: Text('Урон')),
                      DropdownMenuItem(value: BattleEffectType.healing, child: Text('Лечение')),
                      DropdownMenuItem(value: BattleEffectType.temporaryHp, child: Text('Временные хиты')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => effectType = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: effectFormula,
                    decoration: const InputDecoration(labelText: 'Формула эффекта'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: effectTotal,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Результат эффекта'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Комментарий ГМ'),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                String targetCharacter = '';
                String targetLabel = '';
                if (targetType == BattleTargetType.self) {
                  targetCharacter = request.actorCharacterSyncId;
                } else if (targetType == BattleTargetType.ally) {
                  targetCharacter = allySyncId;
                } else {
                  targetLabel = externalTarget.text.trim();
                }
                if (targetType == BattleTargetType.ally && targetCharacter.isEmpty) return;
                if (targetType == BattleTargetType.external && targetLabel.isEmpty) return;

                int? parseInt(TextEditingController controller) {
                  final value = controller.text.trim();
                  if (value.isEmpty) return null;
                  return int.tryParse(value);
                }

                final attackValue = parseInt(attackTotal);
                final effectValue = parseInt(effectTotal);
                if (attackTotal.text.trim().isNotEmpty && attackValue == null) return;
                if (effectTotal.text.trim().isNotEmpty && effectValue == null) return;

                Navigator.pop(
                  context,
                  BattleActionReviewResult(
                    modifications: {
                      'target_type': targetType.dbValue,
                      'target_character_sync_id': targetCharacter,
                      'target_label': targetLabel,
                      'attack_formula': attackFormula.text.trim(),
                      'attack_total': attackValue,
                      'effect_formula': effectFormula.text.trim(),
                      'effect_type': effectType.dbValue,
                      'effect_total': effectValue,
                    },
                    note: note.text.trim(),
                  ),
                );
              },
              child: const Text('Применить изменения'),
            ),
          ],
        );
      },
    ),
  );

  attackTotal.dispose();
  effectTotal.dispose();
  attackFormula.dispose();
  effectFormula.dispose();
  externalTarget.dispose();
  note.dispose();
  return result;
}
