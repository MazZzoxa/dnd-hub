import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/ability_model.dart';
import '../../data/models/attack_model.dart';
import '../../data/models/battle_action_request_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/character_condition_model.dart';
import '../../data/models/custom_action_model.dart';
import '../../domain/providers/gameplay_state_provider.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/spell_model.dart';
import '../../data/repositories/ability_repository.dart';
import '../../data/repositories/attack_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/spell_repository.dart';
import '../../domain/providers/battle_provider.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_service.dart';
import '../../domain/providers/campaign_provider.dart';
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
  bool _actionsReloadScheduled = false;
  int _actionsLoadGeneration = 0;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadActions();
    _syncSubscription = context.read<SyncService>().events.listen(_onSyncEvent);
    // The first load can race with the initial LAN snapshot. Retry after the
    // current frame so the GM view can query the authoritative loadout once
    // the replicated character/session state has been applied locally.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final characterId = widget.character.id;
      if (characterId != null) {
        await context.read<GameplayStateProvider>().loadCharacter(
              characterId,
              widget.character.syncId,
            );
      }
      if (!mounted) return;
      await _loadActions();
    });
  }

  Future<void> _loadActions() async {
    final characterId = widget.character.id;
    final generation = ++_actionsLoadGeneration;
    if (characterId == null) {
      if (mounted && generation == _actionsLoadGeneration) {
        setState(() => _loading = false);
      }
      return;
    }

    final sync = context.read<SyncService>();
    final membership = context.read<CampaignProvider>().currentMembership;
    final isOwnPlayerCharacter =
        sync.role == 'player' &&
        membership?.role == CampaignRole.player &&
        membership?.linkedCharacterId == characterId;

    // The player's own sheet is already the authoritative local source.
    // Do not replace it with an empty/stale server response while the player
    // is reconnecting or while the GM server is still receiving the loadout.
    final localResults = await Future.wait([
      _attackRepository.getForCharacter(characterId),
      _spellRepository.getForCharacter(characterId),
      _abilityRepository.getForCharacter(characterId),
      _inventoryRepository.getForCharacter(characterId),
    ]);
    if (!mounted || generation != _actionsLoadGeneration) return;

    var attacks = localResults[0] as List<AttackModel>;
    var spells = localResults[1] as List<SpellModel>;
    var abilities = localResults[2] as List<AbilityModel>;
    var items = localResults[3] as List<ItemModel>;

    if (!isOwnPlayerCharacter &&
        sync.connected &&
        widget.character.syncId.isNotEmpty) {
      try {
        final loadout = await sync.requestCharacterLoadout(
          characterSyncId: widget.character.syncId,
        );
        if (loadout != null) {
          final remoteAttacks = <AttackModel>[];
          final remoteSpells = <SpellModel>[];
          final remoteAbilities = <AbilityModel>[];
          final remoteItems = <ItemModel>[];

          for (final entry in loadout) {
            final entity = entry['entity']?.toString() ?? '';
            final rawData = entry['data'];
            if (rawData is! Map) continue;
            final data = rawData.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            data['character_id'] = characterId;
            try {
              switch (entity) {
                case 'attack':
                  remoteAttacks.add(AttackModel.fromMap(data));
                  break;
                case 'spell':
                  remoteSpells.add(SpellModel.fromMap(data));
                  break;
                case 'ability':
                  remoteAbilities.add(AbilityModel.fromMap(data));
                  break;
                case 'item':
                  remoteItems.add(ItemModel.fromMap(data));
                  break;
              }
            } catch (_) {
              // Ignore one malformed remote row instead of discarding the
              // other valid actions.
            }
          }

          // Prefer the authoritative network loadout when it contains data.
          // If it is empty, keep a non-empty local cache as a safe fallback;
          // this covers the short window before the player's first publish.
          if (remoteAttacks.isNotEmpty || remoteSpells.isNotEmpty ||
              remoteAbilities.isNotEmpty || remoteItems.isNotEmpty ||
              (attacks.isEmpty && spells.isEmpty &&
                  abilities.isEmpty && items.isEmpty)) {
            attacks = remoteAttacks;
            spells = remoteSpells;
            abilities = remoteAbilities;
            items = remoteItems;
          }
        }
      } catch (_) {
        // Keep the local cache when the network request is unavailable.
      }
    }

    if (!mounted || generation != _actionsLoadGeneration) return;
    setState(() {
      _attacks = attacks;
      _spells = spells;
      _abilities = abilities;
      _items = items;
      _loading = false;
    });
  }

  void _onSyncEvent(NetworkMessage event) {
    final eventName = event.payload['event']?.toString() ?? '';
    final entity = event.payload['entity']?.toString() ?? '';

    // A full snapshot can contain the character's attacks/spells/abilities,
    // but it does not expose them as a single `entity` event. If the screen
    // was opened while that snapshot was still arriving, reload after the
    // snapshot is applied.
    if (eventName == 'state.snapshot') {
      _scheduleActionsReload();
      return;
    }

    if (entity != 'attack' &&
        entity != 'spell' &&
        entity != 'ability' &&
        entity != 'item' &&
        entity != 'custom_action') {
      return;
    }

    final raw = event.payload['data'];
    if (raw is! Map) return;
    final characterSyncId = raw['character_sync_id']?.toString() ?? '';
    if (characterSyncId != widget.character.syncId) return;
    _scheduleActionsReload();
  }

  void _scheduleActionsReload() {
    if (_actionsReloadScheduled) return;
    _actionsReloadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _actionsReloadScheduled = false;
      if (!mounted) return;
      await _loadActions();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final characters = context.watch<CharacterProvider>().characters;
    final character = _currentCharacter(characters);
    final campaigns = context.watch<CampaignProvider>();
    final linkedIds = campaigns.members
        .where((member) => member.role == CampaignRole.player && member.linkedCharacterId != null)
        .map((member) => member.linkedCharacterId!)
        .toSet();
    final campaignCharacters = characters
        .where((character) => character.id != null && linkedIds.contains(character.id))
        .toList(growable: false);
    final battle = context.watch<BattleProvider>();
    final gameplay = context.watch<GameplayStateProvider>();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(character.name),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Обзор'),
              Tab(text: 'Действия'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _overview(character),
            _actions(
              character: character,
              battle: battle,
              availableCharacters: campaignCharacters,
              conditions: gameplay.conditionsFor(character.syncId),
              customActions: gameplay.customActionsFor(character.syncId),
            ),
          ],
        ),
      ),
    );
  }

  CharacterModel _currentCharacter(List<CharacterModel> characters) {
    for (final character in characters) {
      if (character.syncId == widget.character.syncId) return character;
    }
    return widget.character;
  }

  Widget _overview(CharacterModel character) {
    final gameplay = context.watch<GameplayStateProvider>();
    final conditions = gameplay.conditionsFor(character.syncId);
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
        if (character.lifeState != CharacterLifeState.normal || conditions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (character.lifeState != CharacterLifeState.normal) ...[
                    Text(
                      'Состояние',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Chip(
                      avatar: Icon(
                        character.lifeState == CharacterLifeState.dead
                            ? Icons.close
                            : Icons.favorite_border,
                        size: 18,
                      ),
                      label: Text(character.lifeState.label),
                    ),
                    if (character.lifeState == CharacterLifeState.downed)
                      Text(
                        'Успехи спасбросков: ${character.deathSaveSuccesses} · '
                        'Провалы: ${character.deathSaveFailures}',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                  ],
                  if (conditions.isNotEmpty) ...[
                    if (character.lifeState != CharacterLifeState.normal)
                      const SizedBox(height: 12),
                    const Text(
                      'Состояния',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final condition in conditions)
                          ActionChip(
                            avatar: const Icon(
                              Icons.local_fire_department_outlined,
                              size: 16,
                            ),
                            label: Text(condition.name),
                            onPressed: () => _showConditionDetails(condition),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
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
    required CharacterModel character,
    required BattleProvider battle,
    required List<CharacterModel> availableCharacters,
    required List<CharacterConditionModel> conditions,
    required List<CustomActionModel> customActions,
  }) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _loadActions,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _section(
            title: 'Собственные действия',
            icon: Icons.handyman_outlined,
            children: [
              for (final action in customActions)
                _actionTile(
                  name: action.name,
                  details: action.description.isEmpty ? 'Импровизированное действие' : action.description,
                  enabled: widget.canAct,
                  onDetails: () => _showActionDetails(
                    title: action.name,
                    icon: Icons.handyman_outlined,
                    details: [
                      if (action.attackFormula.isNotEmpty) _ActionDetail('Попадание', action.attackFormula),
                      if (action.effectFormula.isNotEmpty) _ActionDetail('Эффект', action.effectFormula),
                      _ActionDetail('Тип эффекта', _effectLabel(action.effectType)),
                    ],
                    description: action.description,
                  ),
                  onUse: () => _useAction(
                    character: character, battle: battle, availableCharacters: availableCharacters, conditions: conditions,
                    actionType: BattleActionType.manual, actionName: action.name, actionSyncId: action.syncId,
                    attackFormula: action.attackFormula, effectFormula: action.effectFormula, effectType: _effectTypeFromString(action.effectType),
                  ),
                ),
              _actionTile(
                name: 'Импровизированное действие',
                details: 'Создать действие на ходу',
                enabled: widget.canAct,
                onDetails: () => _showActionDetails(title: 'Импровизированное действие', icon: Icons.add_circle_outline, details: const [_ActionDetail('Тип', 'Одноразовое или сохранённое')]),
                onUse: () => _useAction(
                  character: character, battle: battle, availableCharacters: availableCharacters, conditions: conditions,
                  actionType: BattleActionType.manual, actionName: 'Импровизированное действие', actionSyncId: '',
                ),
              ),
            ],
          ),
          _section(
            title: 'Атаки',
            icon: Icons.gavel_outlined,
            children: [
              for (final attack in _attacks)
                _actionTile(
                  name: attack.name,
                  details: 'Попадание ${_attackFormulaFor(attack)} · Урон ${attack.damage.isEmpty ? '—' : attack.damage}',
                  enabled: widget.canAct,
                  onDetails: () => _showActionDetails(
                    title: attack.name,
                    icon: Icons.gavel_outlined,
                    details: [
                      _ActionDetail('Бонус атаки', attack.attackBonus.isEmpty ? 'Не указан' : attack.attackBonus),
                      _ActionDetail('Формула попадания', _attackFormulaFor(attack)),
                      _ActionDetail('Урон', attack.damage.isEmpty ? 'Не указан' : attack.damage),
                    ],
                  ),
                  onUse: () => _useAction(
                    character: character,
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
                  onDetails: () => _showActionDetails(
                    title: spell.name,
                    icon: Icons.auto_awesome_outlined,
                    details: [
                      _ActionDetail('Уровень', spell.level == 0 ? 'Заговор' : '${spell.level}'),
                      if (spell.type.trim().isNotEmpty) _ActionDetail('Школа', spell.type),
                      if (spell.castingTime.trim().isNotEmpty) _ActionDetail('Время накладывания', spell.castingTime),
                      if (spell.range.trim().isNotEmpty) _ActionDetail('Дистанция', spell.range),
                      if (spell.components.trim().isNotEmpty) _ActionDetail('Компоненты', spell.components),
                      if (spell.duration.trim().isNotEmpty) _ActionDetail('Длительность', spell.duration),
                      _ActionDetail('Подготовлено', spell.prepared ? 'Да' : 'Нет'),
                    ],
                    description: spell.description,
                    sourceUrl: spell.sourceUrl,
                  ),
                  onUse: () => _useAction(
                    character: character,
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
                  onDetails: () => _showActionDetails(
                    title: ability.name,
                    icon: Icons.extension_outlined,
                    details: [
                      if (ability.source.trim().isNotEmpty) _ActionDetail('Источник', ability.source),
                    ],
                    description: ability.description,
                    sourceUrl: ability.sourceUrl,
                  ),
                  onUse: () => _useAction(
                    character: character,
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
                  onDetails: () => _showActionDetails(
                    title: item.name,
                    icon: Icons.inventory_2_outlined,
                    details: [
                      _ActionDetail('Категория', item.category),
                      _ActionDetail('Количество', '${item.quantity}'),
                      if (item.weight > 0) _ActionDetail('Вес', _formatWeight(item.weight)),
                    ],
                    description: item.description,
                    sourceUrl: item.sourceUrl,
                  ),
                  onUse: () => _useAction(
                    character: character,
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
    required VoidCallback onDetails,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onDetails,
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onDetails,
            tooltip: 'Подробнее',
            icon: const Icon(Icons.info_outline),
          ),
          if (enabled)
            FilledButton.tonal(
              onPressed: onUse,
              child: const Text('Использовать'),
            ),
        ],
      ),
    );
  }

  Future<void> _showActionDetails({
    required String title,
    required IconData icon,
    required List<_ActionDetail> details,
    String description = '',
    String sourceUrl = '',
  }) async {
    final visibleDetails = details.where((detail) => detail.value.trim().isNotEmpty).toList(growable: false);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(title)),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final detail in visibleDetails) ...[
                  Text(detail.label, style: const TextStyle(color: AppTheme.textSecondary)),
                  const SizedBox(height: 2),
                  Text(detail.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                ],
                if (description.trim().isNotEmpty) ...[
                  const Divider(),
                  const SizedBox(height: 10),
                  const Text('Описание', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  SelectableText(description),
                ],
                if (sourceUrl.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Источник', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  SelectableText(sourceUrl),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _showConditionDetails(CharacterConditionModel condition) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(condition.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (condition.sourceLabel.isNotEmpty) Text('Источник: ${condition.sourceLabel}'),
            if (condition.remainingRounds > 0) Text('Осталось: ${condition.remainingRounds} раунд(а)'),
            if (condition.description.isNotEmpty) ...[const SizedBox(height: 10), Text(condition.description)],
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Закрыть'))],
      ),
    );
  }

  String _formatWeight(double value) {
    final normalized = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
    return '$normalized кг';
  }

  String _attackFormulaFor(AttackModel attack) {
    final bonus = attack.attackBonus.trim().replaceAll(' ', '');
    if (bonus.isEmpty || bonus == '—') return '1к20';
    if (bonus.startsWith('+') || bonus.startsWith('-')) {
      return '1к20$bonus';
    }
    return '1к20+$bonus';
  }

  BattleEffectType _effectTypeFromString(String value) => switch (value) {
    'damage' => BattleEffectType.damage,
    'healing' => BattleEffectType.healing,
    'temporary_hp' => BattleEffectType.temporaryHp,
    'condition_apply' => BattleEffectType.conditionApply,
    'condition_remove' => BattleEffectType.conditionRemove,
    _ => BattleEffectType.none,
  };

  String _effectLabel(String value) => switch (value) {
    'damage' => 'Урон',
    'healing' => 'Лечение',
    'temporary_hp' => 'Временные хиты',
    'condition_apply' => 'Наложение состояния',
    'condition_remove' => 'Снятие состояния',
    _ => 'Без эффекта',
  };

  Future<void> _useAction({
    required CharacterModel character,
    required BattleProvider battle,
    required List<CharacterModel> availableCharacters,
    required BattleActionType actionType,
    required String actionName,
    required String actionSyncId,
    List<CharacterConditionModel> conditions = const [],
    String attackFormula = '',
    String effectFormula = '',
    BattleEffectType effectType = BattleEffectType.none,
  }) async {
    final result = await showBattleActionComposer(
      context,
      actionName: actionName,
      actionType: actionType,
      actor: character,
      allies: availableCharacters,
      attackFormula: attackFormula,
      effectFormula: effectFormula,
      effectType: effectType,
      conditions: conditions,
    );
    if (result == null || !mounted) return;

    if (result.saveAction) {
      try {
        await context.read<GameplayStateProvider>().saveCustomAction(
          character: character,
          name: result.actionName,
          description: result.description,
          attackFormula: result.attackFormula,
          effectFormula: result.effectFormula,
          effectType: result.effectType.dbValue,
        );
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }

    try {
      await battle.submitAction(
        actorCharacterSyncId: character.syncId,
        actionType: actionType,
        actionName: result.actionName,
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

class _ActionDetail {
  final String label;
  final String value;

  const _ActionDetail(this.label, this.value);
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
