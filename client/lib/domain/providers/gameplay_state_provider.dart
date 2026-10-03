import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/character_condition_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/custom_action_model.dart';
import '../../data/repositories/character_condition_repository.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/custom_action_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class GameplayStateProvider extends ChangeNotifier {
  final CharacterRepository _characterRepository;
  final CustomActionRepository _customActionRepository;
  final CharacterConditionRepository _conditionRepository;
  final SyncService _syncService;
  StreamSubscription<NetworkMessage>? _subscription;

  GameplayStateProvider({
    CharacterRepository? characterRepository,
    CustomActionRepository? customActionRepository,
    CharacterConditionRepository? conditionRepository,
    required SyncService syncService,
  })  : _characterRepository = characterRepository ?? CharacterRepository(),
        _customActionRepository = customActionRepository ?? CustomActionRepository(),
        _conditionRepository = conditionRepository ?? CharacterConditionRepository(),
        _syncService = syncService {
    _subscription = _syncService.events.listen(_onSyncEvent);
  }

  final Map<String, List<CustomActionModel>> _actions = {};
  final Map<String, List<CharacterConditionModel>> _conditions = {};

  List<CustomActionModel> customActionsFor(String characterSyncId) =>
      List.unmodifiable(_actions[characterSyncId] ?? const []);

  List<CharacterConditionModel> conditionsFor(String characterSyncId) =>
      List.unmodifiable(_conditions[characterSyncId] ?? const []);

  Future<void> loadCharacter(int characterId, String characterSyncId) async {
    final actions = await _customActionRepository.getForCharacter(characterId);
    final conditions = await _conditionRepository.getForCharacter(characterId);
    _actions[characterSyncId] = actions;
    _conditions[characterSyncId] = conditions;
    notifyListeners();
  }

  Future<CustomActionModel> saveCustomAction({
    required CharacterModel character,
    required String name,
    String description = '',
    String attackFormula = '',
    String effectFormula = '',
    String effectType = 'none',
  }) async {
    final characterId = character.id;
    if (characterId == null) throw StateError('У персонажа отсутствует локальный ID.');
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) throw ArgumentError('Название действия не может быть пустым.');
    final now = DateTime.now();
    final items = _actions[character.syncId] ??
        await _customActionRepository.getForCharacter(characterId);
    final action = CustomActionModel(
      syncId: SyncIds.newId(),
      characterId: characterId,
      name: trimmedName,
      description: description.trim(),
      attackFormula: attackFormula.trim(),
      effectFormula: effectFormula.trim(),
      effectType: effectType.trim().isEmpty ? 'none' : effectType.trim(),
      sortOrder: items.length,
      createdAt: now,
      updatedAt: now,
    );
    final id = await _customActionRepository.create(action);
    final created = action.copyWith(id: id);
    await _syncService.publishEntity('custom_action', created.toMap());
    await loadCharacter(characterId, character.syncId);
    return created;
  }

  Future<void> updateCustomAction(CustomActionModel action) async {
    final updated = action.copyWith(updatedAt: DateTime.now());
    await _customActionRepository.update(updated);
    await _syncService.publishEntity('custom_action', updated.toMap());
    await _reloadCharacterBySyncId(updated.characterId, await _characterSyncIdForAction(updated));
  }

  Future<void> deleteCustomAction(CustomActionModel action) async {
    await _customActionRepository.delete(action);
    if (action.syncId.isNotEmpty) {
      await _syncService.publishDelete('custom_action', action.syncId);
    }
    await _reloadCharacterBySyncId(action.characterId, await _characterSyncIdForAction(action));
  }

  Future<void> applyCondition({
    required CharacterModel character,
    required String name,
    String description = '',
    String sourceCharacterSyncId = '',
    String sourceLabel = '',
    int durationRounds = 0,
    int? remainingRounds,
    String scope = 'character',
    String battleSyncId = '',
    String sessionSyncId = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Название состояния не может быть пустым.');
    if (_syncService.connected) {
      await _syncService.applyCharacterCondition(
        characterSyncId: character.syncId,
        name: name.trim(),
        description: description.trim(),
        sourceCharacterSyncId: sourceCharacterSyncId,
        sourceLabel: sourceLabel,
        durationRounds: durationRounds,
        remainingRounds: remainingRounds,
        scope: scope,
        battleSyncId: battleSyncId,
        sessionSyncId: sessionSyncId,
        metadata: metadata,
      );
      return;
    }
    final characterId = character.id;
    if (characterId == null) throw StateError('У персонажа отсутствует локальный ID.');
    final now = DateTime.now();
    final condition = CharacterConditionModel(
      syncId: SyncIds.newId(),
      characterId: characterId,
      characterSyncId: character.syncId,
      name: name.trim(),
      description: description.trim(),
      sourceCharacterSyncId: sourceCharacterSyncId.trim(),
      sourceLabel: sourceLabel.trim(),
      durationRounds: durationRounds.clamp(0, 1 << 20).toInt(),
      remainingRounds: (remainingRounds ?? durationRounds).clamp(0, 1 << 20).toInt(),
      scope: scope,
      active: true,
      metadata: metadata,
      createdAt: now,
      updatedAt: now,
    );
    await _conditionRepository.create(condition);
    await _reloadConditions(character);
  }

  Future<void> removeCondition({
    required CharacterConditionModel condition,
    String battleSyncId = '',
    String sessionSyncId = '',
  }) async {
    if (_syncService.connected) {
      await _syncService.removeCharacterCondition(
        conditionSyncId: condition.syncId,
        battleSyncId: battleSyncId,
        sessionSyncId: sessionSyncId,
      );
      return;
    }
    await _conditionRepository.update(
      condition.copyWith(active: false, remainingRounds: 0, updatedAt: DateTime.now()),
    );
    await _reloadConditionsByIds(condition.characterId, condition.characterSyncId);
  }

  Future<void> setLifeState({
    required CharacterModel character,
    required String lifeState,
    String battleSyncId = '',
    String sessionSyncId = '',
  }) async {
    if (_syncService.connected) {
      await _syncService.setCharacterLifeState(
        characterSyncId: character.syncId,
        lifeState: lifeState,
        battleSyncId: battleSyncId,
        sessionSyncId: sessionSyncId,
      );
      return;
    }
    final parsed = CharacterLifeStateX.fromDb(lifeState);
    final updated = character.copyWith(lifeState: parsed);
    await _characterRepository.update(updated);
  }

  Future<CharacterModel?> findCharacter(String syncId) =>
      _characterRepository.findBySyncId(syncId);

  Future<String> _characterSyncIdForAction(CustomActionModel action) async {
    final character = await _characterRepository.getById(action.characterId);
    return character?.syncId ?? '';
  }

  Future<void> _reloadCharacterBySyncId(int characterId, String syncId) async {
    if (syncId.isEmpty) return;
    final actions = await _customActionRepository.getForCharacter(characterId);
    _actions[syncId] = actions;
    notifyListeners();
  }

  Future<void> _reloadConditions(CharacterModel character) async {
    final conditions = await _conditionRepository.getForCharacter(character.id!);
    _conditions[character.syncId] = conditions;
    notifyListeners();
  }

  Future<void> _reloadConditionsByIds(int characterId, String characterSyncId) async {
    final conditions = await _conditionRepository.getForCharacter(characterId);
    _conditions[characterSyncId] = conditions;
    notifyListeners();
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString() ?? '';
    final data = event.payload['data'];
    if (data is! Map) return;
    if (entity == 'custom_action') {
      final map = data.map((key, value) => MapEntry(key.toString(), value));
      final characterSyncId = map['character_sync_id']?.toString() ?? '';
      if (characterSyncId.isEmpty) return;
      final action = CustomActionModel.fromMap(map);
      // Network payloads intentionally do not carry a local character_id.
      final character = await _characterRepository.findBySyncId(characterSyncId);
      if (character == null) return;
      final actions = await _customActionRepository.getForCharacter(character.id!);
      _actions[characterSyncId] = actions;
      if (action.id == null) notifyListeners();
    } else if (entity == 'character_condition') {
      final map = data.map((key, value) => MapEntry(key.toString(), value));
      final characterSyncId = map['character_sync_id']?.toString() ?? '';
      if (characterSyncId.isEmpty) return;
      final character = await _characterRepository.findBySyncId(characterSyncId);
      if (character == null) return;
      _conditions[characterSyncId] = await _conditionRepository.getForCharacter(character.id!);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
