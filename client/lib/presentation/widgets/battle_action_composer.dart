import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/battle_action_request_model.dart';
import '../../data/models/character_model.dart';
import '../../domain/battle/dice_service.dart';

class BattleActionComposerResult {
  final BattleTargetType targetType;
  final String targetCharacterSyncId;
  final String targetLabel;
  final String attackFormula;
  final int? attackTotal;
  final String effectFormula;
  final BattleEffectType effectType;
  final int? effectTotal;
  final Map<String, dynamic> metadata;

  const BattleActionComposerResult({
    required this.targetType,
    required this.targetCharacterSyncId,
    required this.targetLabel,
    required this.attackFormula,
    required this.attackTotal,
    required this.effectFormula,
    required this.effectType,
    required this.effectTotal,
    required this.metadata,
  });
}

Future<BattleActionComposerResult?> showBattleActionComposer(
  BuildContext context, {
  required String actionName,
  required BattleActionType actionType,
  required CharacterModel actor,
  required List<CharacterModel> allies,
  String attackFormula = '',
  String effectFormula = '',
  BattleEffectType effectType = BattleEffectType.none,
}) async {
  return showModalBottomSheet<BattleActionComposerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _BattleActionComposerSheet(
      actionName: actionName,
      actionType: actionType,
      actor: actor,
      allies: allies,
      initialAttackFormula: attackFormula,
      initialEffectFormula: effectFormula,
      initialEffectType: effectType,
    ),
  );
}

class _BattleActionComposerSheet extends StatefulWidget {
  final String actionName;
  final BattleActionType actionType;
  final CharacterModel actor;
  final List<CharacterModel> allies;
  final String initialAttackFormula;
  final String initialEffectFormula;
  final BattleEffectType initialEffectType;

  const _BattleActionComposerSheet({
    required this.actionName,
    required this.actionType,
    required this.actor,
    required this.allies,
    required this.initialAttackFormula,
    required this.initialEffectFormula,
    required this.initialEffectType,
  });

  @override
  State<_BattleActionComposerSheet> createState() =>
      _BattleActionComposerSheetState();
}

class _BattleActionComposerSheetState
    extends State<_BattleActionComposerSheet> {
  final DiceService _dice = DiceService();
  late final TextEditingController _externalTarget;
  late final TextEditingController _attackFormula;
  late final TextEditingController _effectFormula;

  BattleTargetType _targetType = BattleTargetType.self;
  String _allySyncId = '';
  BattleEffectType _effectType = BattleEffectType.none;
  int? _attackTotal;
  int? _effectTotal;
  int? _attackRawTotal;
  List<int> _attackRolls = const [];
  List<int> _effectRolls = const [];
  String _error = '';

  @override
  void initState() {
    super.initState();
    _externalTarget = TextEditingController();
    final initialFormula = widget.initialAttackFormula.trim();
    _attackFormula = TextEditingController(
      text: initialFormula.isEmpty ? '1к20' : initialFormula,
    );
    _effectFormula = TextEditingController(text: widget.initialEffectFormula);
    _effectType = widget.initialEffectType;
    for (final character in widget.allies) {
      if (character.syncId != widget.actor.syncId) {
        _allySyncId = character.syncId;
        break;
      }
    }
  }

  @override
  void dispose() {
    _externalTarget.dispose();
    _attackFormula.dispose();
    _effectFormula.dispose();
    super.dispose();
  }

  void _rollAttack() {
    try {
      final result = _dice.roll(_attackFormula.text);
      setState(() {
        _attackRawTotal = result.total;
        _attackTotal = result.total;
        _attackRolls = result.rolls;
        _error = '';
      });
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  void _rollEffect() {
    try {
      final result = _dice.roll(_effectFormula.text);
      setState(() {
        _effectTotal = result.total;
        _effectRolls = result.rolls;
        _error = '';
      });
    } catch (error) {
      setState(() => _error = '$error');
    }
  }

  void _submit() {
    final formulaAttack = _attackFormula.text.trim();
    final formulaEffect = _effectFormula.text.trim();
    var targetCharacterSyncId = '';
    var targetLabel = '';

    switch (_targetType) {
      case BattleTargetType.self:
        targetCharacterSyncId = widget.actor.syncId;
        break;
      case BattleTargetType.ally:
        if (_allySyncId.isEmpty) {
          setState(() => _error = 'Выберите союзника.');
          return;
        }
        targetCharacterSyncId = _allySyncId;
        break;
      case BattleTargetType.external:
        targetLabel = _externalTarget.text.trim();
        if (targetLabel.isEmpty) {
          setState(() => _error = 'Укажите внешнюю цель.');
          return;
        }
        break;
    }

    if (_attackTotal != null && _attackTotal! < 0) {
      setState(() => _error = 'Результат попадания не может быть отрицательным.');
      return;
    }
    if (_effectType != BattleEffectType.none && _effectTotal == null) {
      setState(() => _error = 'Для эффекта сначала сделайте бросок.');
      return;
    }

    Navigator.of(context).pop(
      BattleActionComposerResult(
        targetType: _targetType,
        targetCharacterSyncId: targetCharacterSyncId,
        targetLabel: targetLabel,
        attackFormula: formulaAttack,
        attackTotal: _attackTotal,
        effectFormula: formulaEffect,
        effectType: _effectType,
        effectTotal: _effectTotal,
        metadata: {
          'actor_name': widget.actor.name,
          'attack_rolls': _attackRolls,
          'attack_raw_total': _attackRawTotal,
          'effect_rolls': _effectRolls,
          'target_name': _targetName(targetCharacterSyncId, targetLabel),
        },
      ),
    );
  }

  String _targetName(String syncId, String label) {
    if (label.isNotEmpty) return label;
    if (syncId == widget.actor.syncId) return widget.actor.name;
    for (final character in widget.allies) {
      if (character.syncId == syncId) return character.name;
    }
    return syncId;
  }

  String _actionTypeLabel(BattleActionType type) => switch (type) {
        BattleActionType.attack => 'Атака',
        BattleActionType.spell => 'Заклинание',
        BattleActionType.ability => 'Способность',
        BattleActionType.item => 'Предмет',
        BattleActionType.manual => 'Действие',
      };

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flash_on_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.actionName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  _actionTypeLabel(widget.actionType),
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<BattleTargetType>(
              value: _targetType,
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
                if (value == null) return;
                setState(() => _targetType = value);
              },
            ),
            if (_targetType == BattleTargetType.ally) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _allySyncId.isEmpty ? null : _allySyncId,
                decoration: const InputDecoration(labelText: 'Союзник'),
                items: [
                  for (final character in widget.allies)
                    if (character.syncId != widget.actor.syncId)
                      DropdownMenuItem(
                        value: character.syncId,
                        child: Text(character.name),
                      ),
                ],
                onChanged: (value) => setState(() => _allySyncId = value ?? ''),
              ),
            ],
            if (_targetType == BattleTargetType.external) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _externalTarget,
                decoration: const InputDecoration(
                  labelText: 'Название цели',
                  hintText: 'Гоблин 2',
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Попадание',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            _RollField(
              title: 'Формула попадания',
              hint: '1к20 или 1к20 + 5',
              controller: _attackFormula,
              total: _attackTotal,
              resultLabel: 'Результат попадания',
              onRoll: _rollAttack,
              enabled: _attackFormula.text.trim().isNotEmpty,
              onChanged: (_) => setState(() {
                _attackTotal = null;
                _attackRawTotal = null;
                _attackRolls = const [];
              }),
            ),
            const SizedBox(height: 16),
            const Text(
              'Урон и эффект',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<BattleEffectType>(
              value: _effectType,
              decoration: const InputDecoration(labelText: 'Эффект'),
              items: const [
                DropdownMenuItem(
                  value: BattleEffectType.none,
                  child: Text('Без эффекта'),
                ),
                DropdownMenuItem(
                  value: BattleEffectType.damage,
                  child: Text('Урон'),
                ),
                DropdownMenuItem(
                  value: BattleEffectType.healing,
                  child: Text('Лечение'),
                ),
                DropdownMenuItem(
                  value: BattleEffectType.temporaryHp,
                  child: Text('Временные хиты'),
                ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _effectType = value;
                  if (value == BattleEffectType.none) {
                    _effectTotal = null;
                    _effectRolls = const [];
                  }
                });
              },
            ),
            if (_effectType != BattleEffectType.none) ...[
              const SizedBox(height: 12),
              _RollField(
                title: switch (_effectType) {
                  BattleEffectType.damage => 'Формула урона',
                  BattleEffectType.healing => 'Формула лечения',
                  BattleEffectType.temporaryHp => 'Формула временных хитов',
                  BattleEffectType.none => 'Формула эффекта',
                },
                hint: switch (_effectType) {
                  BattleEffectType.damage => '1к8 + 3',
                  BattleEffectType.healing => '1к8 + 4',
                  BattleEffectType.temporaryHp => '1к4 + 4',
                  BattleEffectType.none => '1к8',
                },
                controller: _effectFormula,
                total: _effectTotal,
                onRoll: _rollEffect,
                enabled: _effectFormula.text.trim().isNotEmpty,
                onChanged: (_) => setState(() {
                  _effectTotal = null;
                  _effectRolls = const [];
                }),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: AppTheme.danger)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.send_outlined),
                label: const Text('Передать ГМ'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RollField extends StatelessWidget {
  final String title;
  final String hint;
  final TextEditingController controller;
  final int? total;
  final String resultLabel;
  final VoidCallback onRoll;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _RollField({
    required this.title,
    required this.hint,
    required this.controller,
    required this.total,
    this.resultLabel = 'Результат',
    required this.onRoll,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: title,
            hintText: hint,
            suffixIcon: IconButton(
              tooltip: 'Бросить кубики',
              onPressed: enabled ? onRoll : null,
              icon: const Icon(Icons.casino_outlined),
            ),
          ),
          onChanged: onChanged,
        ),
        if (total != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '$resultLabel: $total',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}
