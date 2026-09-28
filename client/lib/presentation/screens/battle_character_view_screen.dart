import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/ability_model.dart';
import '../../data/models/attack_model.dart';
import '../../data/models/battle_action_request_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/spell_model.dart';
import '../../data/repositories/ability_repository.dart';
import '../../data/repositories/attack_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/spell_repository.dart';
import '../../domain/providers/battle_provider.dart';
import '../../domain/providers/character_provider.dart';
import '../widgets/battle_action_composer.dart';

class BattleCharacterViewScreen extends StatefulWidget {
  final CharacterModel character;
  final bool canAct;

  const BattleCharacterViewScreen({
    super.key,
    required this.character,
    required this.canAct,
  });

  @override
  State<BattleCharacterViewScreen> createState() =>
      _BattleCharacterViewScreenState();
}

class _BattleCharacterViewScreenState
    extends State<BattleCharacterViewScreen> {
  final _attackRepository = AttackRepository();
  final _spellRepository = SpellRepository();
  final _abilityRepository = AbilityRepository();
  final _inventoryRepository = InventoryRepository();

  List<AttackModel> _attacks = [];
  List<SpellModel> _spells = [];
  List<AbilityModel> _abilities = [];
  List<ItemModel> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  Future<void> _loadActions() async {
    final characterId = widget.character.id;
    if (characterId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      _attackRepository.getForCharacter(characterId),
      _spellRepository.getForCharacter(characterId),
      _abilityRepository.getForCharacter(characterId),
      _inventoryRepository.getForCharacter(characterId),
    ]);
    if (!mounted) return;
    setState(() {
      _attacks = results[0] as List<AttackModel>;
      _spells = results[1] as List<SpellModel>;
      _abilities = results[2] as List<AbilityModel>;
      _items = results[3] as List<ItemModel>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final characters = context.watch<CharacterProvider>().characters;
    final battle = context.watch<BattleProvider>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.character.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Обзор'),
              Tab(text: 'Действия'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _overview(),
            _actions(
              battle: battle,
              availableCharacters: characters,
            ),
          ],
        ),
      ),
    );
  }

  Widget _overview() {
    final character = widget.character;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 24,
                      child: Icon(Icons.person_outline),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            character.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${character.race} · ${character.className} · Уровень ${character.level}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _StatBox(label: 'Хиты', value: '${character.hp}/${character.maxHp}'),
                    _StatBox(label: 'Врем. хиты', value: '${character.temporaryHp}'),
                    _StatBox(label: 'КД', value: '${character.armorClass}'),
                    _StatBox(
                      label: 'Инициатива',
                      value: _signed(character.initiative),
                    ),
                    _StatBox(label: 'Скорость', value: '${character.speed}'),
                    _StatBox(
                      label: 'Бонус мастерства',
                      value: _signed(character.proficiencyBonus),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Основные характеристики',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _AbilityScore('СИЛ', character.strength),
                    _AbilityScore('ЛОВ', character.dexterity),
                    _AbilityScore('ТЕЛ', character.constitution),
                    _AbilityScore('ИНТ', character.intelligence),
                    _AbilityScore('МДР', character.wisdom),
                    _AbilityScore('ХАР', character.charisma),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (!widget.canAct)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Просмотр боевых параметров. Действия доступны владельцу персонажа только во время его хода.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _actions({
    required BattleProvider battle,
    required List<CharacterModel> availableCharacters,
  }) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadActions,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: 'Атаки',
            icon: Icons.gavel_outlined,
            children: [
              for (final attack in _attacks)
                _actionTile(
                  name: attack.name,
                  details: 'Попадание ${_attackFormulaFor(attack)} · Урон ${attack.damage.isEmpty ? '—' : attack.damage}',
                  enabled: widget.canAct,
                  onUse: () => _useAction(
                    battle: battle,
                    availableCharacters: availableCharacters,
                    actionType: BattleActionType.attack,
                    actionName: attack.name,
                    actionSyncId: attack.syncId,
                    attackFormula: _attackFormulaFor(attack),
                    effectFormula: _asFormula(attack.damage),
                    effectType: attack.damage.trim().isEmpty
                        ? BattleEffectType.none
                        : BattleEffectType.damage,
                  ),
                ),
            ],
          ),
          _section(
            title: 'Заклинания',
            icon: Icons.auto_awesome_outlined,
            children: [
              for (final spell in _spells)
                _actionTile(
                  name: spell.name,
                  details: 'Уровень ${spell.level == 0 ? 'заговор' : spell.level} · ${spell.castingTime.isEmpty ? 'Время не указано' : spell.castingTime}',
                  enabled: widget.canAct,
                  onUse: () => _useAction(
                    battle: battle,
                    availableCharacters: availableCharacters,
                    actionType: BattleActionType.spell,
                    actionName: spell.name,
                    actionSyncId: spell.syncId,
                  ),
                ),
            ],
          ),
          _section(
            title: 'Способности',
            icon: Icons.extension_outlined,
            children: [
              for (final ability in _abilities)
                _actionTile(
                  name: ability.name,
                  details: ability.description,
                  enabled: widget.canAct,
                  onUse: () => _useAction(
                    battle: battle,
                    availableCharacters: availableCharacters,
                    actionType: BattleActionType.ability,
                    actionName: ability.name,
                    actionSyncId: ability.syncId,
                  ),
                ),
            ],
          ),
          _section(
            title: 'Предметы',
            icon: Icons.inventory_2_outlined,
            children: [
              for (final item in _items)
                _actionTile(
                  name: item.name,
                  details: '${item.category} · Количество ${item.quantity}',
                  enabled: widget.canAct,
                  onUse: () => _useAction(
                    battle: battle,
                    availableCharacters: availableCharacters,
                    actionType: BattleActionType.item,
                    actionName: item.name,
                    actionSyncId: item.syncId,
                  ),
                ),
            ],
          ),
          if (_attacks.isEmpty &&
              _spells.isEmpty &&
              _abilities.isEmpty &&
              _items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'У персонажа нет доступных действий для боя.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(icon),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${children.length}',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
              if (children.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...children,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionTile({
    required String name,
    required String details,
    required bool enabled,
    required VoidCallback onUse,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: enabled
          ? FilledButton.tonal(
              onPressed: onUse,
              child: const Text('Использовать'),
            )
          : null,
    );
  }

  String _attackFormulaFor(AttackModel attack) {
    final bonus = attack.attackBonus.trim().replaceAll(' ', '');
    if (bonus.isEmpty || bonus == '—') return '1к20';
    if (bonus.startsWith('+') || bonus.startsWith('-')) {
      return '1к20$bonus';
    }
    return '1к20+$bonus';
  }

  Future<void> _useAction({
    required BattleProvider battle,
    required List<CharacterModel> availableCharacters,
    required BattleActionType actionType,
    required String actionName,
    required String actionSyncId,
    String attackFormula = '',
    String effectFormula = '',
    BattleEffectType effectType = BattleEffectType.none,
  }) async {
    final result = await showBattleActionComposer(
      context,
      actionName: actionName,
      actionType: actionType,
      actor: widget.character,
      allies: availableCharacters,
      attackFormula: attackFormula,
      effectFormula: effectFormula,
      effectType: effectType,
    );
    if (result == null || !mounted) return;

    try {
      await battle.submitAction(
        actorCharacterSyncId: widget.character.syncId,
        actionType: actionType,
        actionName: actionName,
        actionSyncId: actionSyncId,
        targetType: result.targetType,
        targetCharacterSyncId: result.targetCharacterSyncId,
        targetLabel: result.targetLabel,
        attackFormula: result.attackFormula,
        attackTotal: result.attackTotal,
        effectFormula: result.effectFormula,
        effectType: result.effectType,
        effectTotal: result.effectTotal,
        metadata: result.metadata,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запрос действия отправлен ГМ.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error')),
        );
      }
    }
  }

  String _asFormula(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '—') return '';
    return normalized.replaceAll(RegExp(r'[dD]'), 'к');
  }

  String _signed(int value) => value >= 0 ? '+$value' : '$value';
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;

  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _AbilityScore extends StatelessWidget {
  final String label;
  final int value;

  const _AbilityScore(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final modifier = ((value - 10) / 2).floor();
    return Chip(
      label: Text('$label $value (${modifier >= 0 ? '+' : ''}$modifier)'),
    );
  }
}
