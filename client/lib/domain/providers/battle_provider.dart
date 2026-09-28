import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/battle_action_request_model.dart';
import '../../data/models/battle_log_entry_model.dart';
import '../../data/models/battle_model.dart';
import '../../data/models/battle_projection_model.dart';
import '../../data/models/battle_turn_model.dart';
import '../../data/models/session_model.dart';
import '../../data/repositories/battle_action_request_repository.dart';
import '../../data/repositories/battle_log_repository.dart';
import '../../data/repositories/battle_repository.dart';
import '../../data/repositories/battle_turn_repository.dart';
import '../../data/repositories/campaign_repository.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';
import '../battle/battle_rules.dart';
import '../battle/battle_service.dart';

enum BattleOperation { damage, heal, temporaryHp }

class BattleProvider extends ChangeNotifier {
  final BattleRepository _repository;
  final CharacterRepository _characterRepository;
  final CampaignRepository _campaignRepository;
  final SessionRepository _sessionRepository;
  final BattleTurnRepository _turnRepository;
  final BattleActionRequestRepository _actionRequestRepository;
  final BattleLogRepository _logRepository;
  final SyncService? _syncService;
  final BattleService _service;
  StreamSubscription<NetworkMessage>? _syncSubscription;
  Future<void> _syncEventQueue = Future<void>.value();

  BattleProvider({
    BattleRepository? repository,
    CharacterRepository? characterRepository,
    CampaignRepository? campaignRepository,
    SessionRepository? sessionRepository,
    BattleTurnRepository? turnRepository,
    BattleActionRequestRepository? actionRequestRepository,
    BattleLogRepository? logRepository,
    SyncService? syncService,
    BattleService service = const BattleService(),
  })  : _repository = repository ?? BattleRepository(),
        _characterRepository = characterRepository ?? CharacterRepository(),
        _campaignRepository = campaignRepository ?? CampaignRepository(),
        _sessionRepository = sessionRepository ?? SessionRepository(),
        _turnRepository = turnRepository ?? BattleTurnRepository(),
        _actionRequestRepository =
            actionRequestRepository ?? BattleActionRequestRepository(),
        _logRepository = logRepository ?? BattleLogRepository(),
        _syncService = syncService,
        _service = service {
    _syncSubscription = _syncService?.events.listen(_enqueueSyncEvent);
  }

  List<BattleModel> _battles = [];
  BattleModel? _active;
  final Map<String, BattleProjectionModel> _projections = {};
  List<BattleTurnModel> _turns = [];
  BattleTurnModel? _currentTurn;
  List<BattleActionRequestModel> _actionRequests = [];
  List<BattleLogEntryModel> _journal = [];
  int? _campaignId;
  int? _sessionId;
  bool _loading = false;
  DiceDisplay? _lastDice;

  List<BattleModel> get battles => List.unmodifiable(_battles);
  BattleModel? get active => _active;
  bool get isActive => _active?.status == BattleStatus.active;
  Map<String, BattleProjectionModel> get projections =>
      Map.unmodifiable(_projections);
  List<BattleTurnModel> get turns => List.unmodifiable(_turns);
  BattleTurnModel? get currentTurn => _currentTurn;
  List<BattleActionRequestModel> get actionRequests =>
      List.unmodifiable(_actionRequests);
  List<BattleActionRequestModel> get pendingActionRequests =>
      List.unmodifiable(
        _actionRequests.where(
          (request) =>
              request.status == BattleActionRequestStatus.pendingGm,
        ),
      );
  List<BattleLogEntryModel> get journal => List.unmodifiable(_journal);
  bool get loading => _loading;
  DiceDisplay? get lastDice => _lastDice;
  int? get activeSessionId => _active?.sessionId;
  String get activeBattleSyncId => _active?.syncId ?? '';
  String get role => _syncService?.role ?? '';
  String get clientId => _syncService?.clientId ?? '';

  Future<void> loadForSession({
    required int campaignId,
    required int sessionId,
  }) async {
    _campaignId = campaignId;
    _sessionId = sessionId;
    _loading = true;
    notifyListeners();

    _battles = await _repository.getForSession(sessionId);
    _active = null;
    _projections.clear();
    _turns = [];
    _currentTurn = null;
    _actionRequests = [];
    _journal = [];
    for (final battle in _battles) {
      if (battle.status == BattleStatus.active) {
        _active = battle;
        break;
      }
    }

    if (_active != null) {
      await _loadWorkspace(_active!.syncId);
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> _loadWorkspace(String battleSyncId) async {
    if (battleSyncId.trim().isEmpty) return;
    _turns = await _turnRepository.getForBattle(battleSyncId);
    _currentTurn = await _turnRepository.getActive(battleSyncId);
    _actionRequests = await _actionRequestRepository.getForBattle(battleSyncId);
    _journal = await _logRepository.getRecentForBattle(
      battleSyncId,
      limit: 100,
    );
  }

  Future<void> startBattle(SessionModel session) async {
    if (session.id == null || session.syncId.trim().isEmpty) {
      throw StateError(
        'У сессии отсутствует локальный или сетевой идентификатор.',
      );
    }
    final active = await _repository.getActive(session.id!);
    _service.validateStart(session: session, activeBattle: active);

    if (_syncService?.connected == true) {
      await _syncService!.startBattle(sessionSyncId: session.syncId);
      return;
    }

    if (_syncService?.role != 'gm') {
      throw StateError(
        'Для боевого режима игрока требуется подключение к серверу ГМ.',
      );
    }

    final now = DateTime.now();
    final localBattle = BattleModel(
      syncId: SyncIds.newId(),
      campaignId: session.campaignId,
      sessionId: session.id!,
      status: BattleStatus.active,
      createdAt: now,
      startedAt: now,
      updatedAt: now,
    );
    await _repository.create(localBattle);
    await loadForSession(
      campaignId: session.campaignId,
      sessionId: session.id!,
    );
  }

  Future<void> endBattle() async {
    final battle = _active;
    if (battle == null) {
      throw StateError('Активного боя нет.');
    }
    _service.validateActiveBattle(battle);

    if (_syncService?.connected == true) {
      if (_currentTurn != null) {
        await _syncService!.endBattleTurn(
          battleSyncId: battle.syncId,
          turnSyncId: _currentTurn!.syncId,
        );
      }
      await _syncService!.endBattle(battleSyncId: battle.syncId);
      await loadForSession(
        campaignId: battle.campaignId,
        sessionId: battle.sessionId,
      );
      _projections.clear();
      notifyListeners();
      return;
    }

    if (_syncService?.role != 'gm') {
      throw StateError(
        'Для завершения боя требуется подключение к серверу ГМ.',
      );
    }

    if (_currentTurn != null) {
      final ended = _currentTurn!.copyWith(
        status: BattleTurnStatus.completed,
        endedAt: DateTime.now(),
      );
      await _turnRepository.update(ended);
      await _appendLocalJournal(
        battle.syncId,
        type: 'turn_ended',
        actorCharacterSyncId: ended.characterSyncId,
        turnSequence: ended.sequence,
      );
    }

    final now = DateTime.now();
    final completed = battle.copyWith(
      status: BattleStatus.completed,
      endedAt: now,
      updatedAt: now,
    );
    await _repository.update(completed);
    await loadForSession(
      campaignId: completed.campaignId,
      sessionId: completed.sessionId,
    );
    _projections.clear();
    notifyListeners();
  }

  Future<void> startTurn({required String characterSyncId}) async {
    final battle = _active;
    _service.validateActiveBattle(battle);
    final characterId = characterSyncId.trim();
    if (characterId.isEmpty) throw StateError('Не выбран персонаж.');

    if (_syncService?.connected == true) {
      await _syncService!.startBattleTurn(
        battleSyncId: battle!.syncId,
        characterSyncId: characterId,
      );
      return;
    }
    if (_syncService?.role != 'gm') {
      throw StateError('Только ГМ может управлять ходами в бою.');
    }
    final character = await _characterRepository.findBySyncId(characterId);
    if (character == null) throw StateError('Персонаж не найден.');

    final current = _currentTurn;
    if (current != null) {
      final ended = current.copyWith(
        status: BattleTurnStatus.completed,
        endedAt: DateTime.now(),
      );
      await _turnRepository.update(ended);
      await _appendLocalJournal(
        battle!.syncId,
        type: 'turn_ended',
        actorCharacterSyncId: ended.characterSyncId,
        turnSequence: ended.sequence,
      );
    }

    final turn = BattleTurnModel(
      syncId: SyncIds.newId(),
      battleSyncId: battle!.syncId,
      characterSyncId: characterId,
      sequence: (_turns.isEmpty ? 0 : _turns.last.sequence) + 1,
      status: BattleTurnStatus.active,
      startedAt: DateTime.now(),
    );
    final id = await _turnRepository.create(turn);
    _currentTurn = turn.copyWith(id: id);
    await _appendLocalJournal(
      battle.syncId,
      type: 'turn_started',
      actorCharacterSyncId: characterId,
      turnSequence: turn.sequence,
    );
    await _loadWorkspace(battle.syncId);
    notifyListeners();
  }

  Future<void> endTurn() async {
    final battle = _active;
    _service.validateActiveBattle(battle);
    final turn = _currentTurn;
    if (turn == null) throw StateError('Активного хода нет.');

    if (_syncService?.connected == true) {
      await _syncService!.endBattleTurn(
        battleSyncId: battle!.syncId,
        turnSyncId: turn.syncId,
      );
      return;
    }
    if (_syncService?.role != 'gm') {
      throw StateError('Только GM может завершить ход.');
    }
    final ended = turn.copyWith(
      status: BattleTurnStatus.completed,
      endedAt: DateTime.now(),
    );
    await _turnRepository.update(ended);
    await _appendLocalJournal(
      battle!.syncId,
      type: 'turn_ended',
      actorCharacterSyncId: turn.characterSyncId,
      turnSequence: turn.sequence,
    );
    await _loadWorkspace(battle.syncId);
    notifyListeners();
  }

  Future<void> submitAction({
    required String actorCharacterSyncId,
    required BattleActionType actionType,
    required String actionName,
    String actionSyncId = '',
    required BattleTargetType targetType,
    String targetCharacterSyncId = '',
    String targetLabel = '',
    String attackFormula = '',
    int? attackTotal,
    String effectFormula = '',
    BattleEffectType effectType = BattleEffectType.none,
    int? effectTotal,
    Map<String, dynamic> metadata = const {},
  }) async {
    final battle = _active;
    _service.validateActiveBattle(battle);
    final turn = _currentTurn;
    if (turn == null) throw StateError('Сейчас нет активного хода.');
    if (turn.characterSyncId != actorCharacterSyncId) {
      throw StateError('Сейчас ход другого персонажа.');
    }
    if (_syncService?.connected != true) {
      throw StateError('Для отправки запроса действия требуется подключение к серверу ГМ.');
    }

    await _syncService!.submitBattleAction({
      'battle_sync_id': battle!.syncId,
      'actor_character_sync_id': actorCharacterSyncId,
      'action_type': actionType.dbValue,
      'action_sync_id': actionSyncId,
      'action_name': actionName,
      'target_type': targetType.dbValue,
      'target_character_sync_id': targetCharacterSyncId,
      'target_label': targetLabel,
      'attack_formula': attackFormula,
      'attack_total': attackTotal,
      'effect_formula': effectFormula,
      'effect_type': effectType.dbValue,
      'effect_total': effectTotal,
      'metadata': metadata,
    });
  }

  Future<void> approveAction(
    BattleActionRequestModel request, {
    String note = '',
  }) async {
    _validateResolvableRequest(request);
    if (_syncService?.connected != true) {
      throw StateError('Для подтверждения запроса действия требуется локальная сеть.');
    }
    await _syncService!.approveBattleAction(
      actionRequestSyncId: request.syncId,
      note: note,
    );
  }

  Future<void> rejectAction(
    BattleActionRequestModel request, {
    required String reason,
  }) async {
    _validateResolvableRequest(request);
    if (_syncService?.connected != true) {
      throw StateError('Для решения запроса действия требуется локальная сеть.');
    }
    await _syncService!.rejectBattleAction(
      actionRequestSyncId: request.syncId,
      reason: reason,
    );
  }

  Future<void> modifyAction(
    BattleActionRequestModel request, {
    required Map<String, dynamic> modifications,
    String note = '',
  }) async {
    _validateResolvableRequest(request);
    if (_syncService?.connected != true) {
      throw StateError('Для изменения запроса действия требуется локальная сеть.');
    }
    await _syncService!.modifyBattleAction(
      actionRequestSyncId: request.syncId,
      modifications: modifications,
      note: note,
    );
  }

  void _validateResolvableRequest(BattleActionRequestModel request) {
    final battle = _active;
    _service.validateActiveBattle(battle);
    if (request.battleSyncId != battle!.syncId) {
      throw StateError('Запрос действия относится к другому бою.');
    }
    if (request.status != BattleActionRequestStatus.pendingGm) {
      throw StateError('Запрос действия уже обработан.');
    }
  }

  Future<void> damage({
    required String characterSyncId,
    required int amount,
  }) async {
    await _performCharacterAction(
      characterSyncId: characterSyncId,
      amount: amount,
      operation: BattleOperation.damage,
      send: (battleId, characterId, value) => _syncService!.applyDamage(
        battleSyncId: battleId,
        characterSyncId: characterId,
        amount: value,
      ),
    );
  }

  Future<void> heal({
    required String characterSyncId,
    required int amount,
  }) async {
    await _performCharacterAction(
      characterSyncId: characterSyncId,
      amount: amount,
      operation: BattleOperation.heal,
      send: (battleId, characterId, value) => _syncService!.heal(
        battleSyncId: battleId,
        characterSyncId: characterId,
        amount: value,
      ),
    );
  }

  Future<void> setTemporaryHp({
    required String characterSyncId,
    required int amount,
  }) async {
    await _performCharacterAction(
      characterSyncId: characterSyncId,
      amount: amount,
      operation: BattleOperation.temporaryHp,
      send: (battleId, characterId, value) => _syncService!.setTemporaryHp(
        battleSyncId: battleId,
        characterSyncId: characterId,
        amount: value,
      ),
    );
  }

  Future<void> _performCharacterAction({
    required String characterSyncId,
    required int amount,
    required BattleOperation operation,
    required Future<void> Function(
      String battleId,
      String characterId,
      int value,
    ) send,
  }) async {
    final battle = _active;
    _service.validateActiveBattle(battle);
    if (characterSyncId.trim().isEmpty) {
      throw StateError('Не выбран персонаж.');
    }
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Значение не может быть отрицательным.',
      );
    }

    if (_syncService?.connected == true) {
      if (_syncService?.role != 'gm') {
        throw StateError('Прямое изменение состояния доступно только ГМ.');
      }
      await send(battle!.syncId, characterSyncId, amount);
      return;
    }

    if (_syncService?.role != 'gm') {
      throw StateError('Нет подключения к серверу ГМ.');
    }

    final character = await _characterRepository.findBySyncId(characterSyncId);
    if (character == null) {
      throw StateError('Персонаж не найден.');
    }

    final hpBefore = character.hp;
    final temporaryBefore = character.temporaryHp;
    final updated = switch (operation) {
      BattleOperation.damage => BattleRules.applyDamage(character, amount),
      BattleOperation.heal => BattleRules.heal(character, amount),
      BattleOperation.temporaryHp =>
        BattleRules.setTemporaryHp(character, amount),
    };
    await _characterRepository.update(updated);
    await _appendLocalJournal(
      battle!.syncId,
      type: switch (operation) {
        BattleOperation.damage => 'damage_applied',
        BattleOperation.heal => 'healing_applied',
        BattleOperation.temporaryHp => 'temporary_hp_applied',
      },
      targetCharacterSyncId: characterSyncId,
      amount: amount,
      metadata: {
        'source': 'gm_direct',
        'hp_before': hpBefore,
        'hp_after': updated.hp,
        'temporary_hp_before': temporaryBefore,
        'temporary_hp_after': updated.temporaryHp,
      },
    );
    notifyListeners();
  }

  void setDiceResult(DiceDisplay result) {
    _lastDice = result;
    notifyListeners();
  }

  bool isCurrentTurnFor(String characterSyncId) =>
      isActive &&
      _currentTurn?.status == BattleTurnStatus.active &&
      _currentTurn?.characterSyncId == characterSyncId;

  BattleActionRequestModel? pendingActionForCharacter(String characterSyncId) {
    for (final request in pendingActionRequests) {
      if (request.actorCharacterSyncId == characterSyncId) return request;
    }
    return null;
  }

  void _enqueueSyncEvent(NetworkMessage event) {
    final next = _syncEventQueue.then((_) => _onSyncEvent(event));
    _syncEventQueue = next.catchError((_) {});
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final eventName = event.payload['event']?.toString() ?? '';
    final entity = event.payload['entity']?.toString() ?? '';

    if (eventName == 'battle.started' ||
        eventName == 'battle.state' ||
        eventName == 'battle.snapshot' ||
        eventName == 'battle.ended') {
      await _restoreContextFromBattleEvent(event.payload['battle']);
      final campaignId = _campaignId;
      final sessionId = _sessionId;
      if (campaignId != null && sessionId != null) {
        await loadForSession(
          campaignId: campaignId,
          sessionId: sessionId,
        );
      }
      if (eventName == 'battle.ended') {
        _projections.clear();
      } else {
        _updateProjections(event.payload['projections']);
      }
      return;
    }

    if (eventName == 'state.snapshot') {
      await _restoreContextFromCampaignSyncId(event.campaignId);
      final campaignId = _campaignId;
      if (campaignId != null) {
        final activeSession = await _sessionRepository.getActive(campaignId);
        if (activeSession?.id != null) {
          _sessionId = activeSession!.id;
        }
      }
      final campaignIdNow = _campaignId;
      final sessionIdNow = _sessionId;
      if (campaignIdNow != null && sessionIdNow != null) {
        await loadForSession(
          campaignId: campaignIdNow,
          sessionId: sessionIdNow,
        );
      }
      return;
    }

    if ((eventName.startsWith('battle.turn.') ||
            eventName.startsWith('battle.action.') ||
            eventName == 'battle.journal.entry') &&
        _active != null) {
      final data = event.payload['data'];

      // Workspace events are already persisted by SyncService before this
      // provider receives them. Update the in-memory workspace directly from
      // the event instead of re-querying SQLite for every journal/action
      // event. A single player action can generate several events in a row;
      // avoiding repeated full workspace reads keeps the GM screen responsive
      // and prevents transient rebuilds while those events are being applied.
      if (data is Map && entity == 'battle_turn') {
        final turn = BattleTurnModel.fromMap(
          data.map((key, value) => MapEntry(key.toString(), value)),
        );
        final index = _turns.indexWhere((item) => item.syncId == turn.syncId);
        if (index == -1) {
          _turns = [..._turns, turn]
            ..sort((a, b) => a.sequence.compareTo(b.sequence));
        } else {
          final next = List<BattleTurnModel>.from(_turns);
          next[index] = turn;
          next.sort((a, b) => a.sequence.compareTo(b.sequence));
          _turns = next;
        }
        _currentTurn = turn.status == BattleTurnStatus.active ? turn : null;
      } else if (data is Map && entity == 'battle_action_request') {
        final request = BattleActionRequestModel.fromMap(
          data.map((key, value) => MapEntry(key.toString(), value)),
        );
        final index = _actionRequests.indexWhere(
          (item) => item.syncId == request.syncId,
        );
        if (index == -1) {
          _actionRequests = [..._actionRequests, request]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        } else {
          final next = List<BattleActionRequestModel>.from(_actionRequests);
          next[index] = request;
          next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _actionRequests = next;
        }
      } else if (data is Map && entity == 'battle_log_entry') {
        final entry = BattleLogEntryModel.fromMap(
          data.map((key, value) => MapEntry(key.toString(), value)),
        );
        final index = _journal.indexWhere((item) => item.syncId == entry.syncId);
        if (index == -1) {
          _journal = [..._journal, entry]
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        } else {
          final next = List<BattleLogEntryModel>.from(_journal);
          next[index] = entry;
          next.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          _journal = next;
        }
        if (_journal.length > 100) {
          _journal = _journal.sublist(_journal.length - 100);
        }
      } else {
        await _loadWorkspace(_active!.syncId);
      }

      notifyListeners();
      return;
    }

    if (entity == 'battle' && _campaignId != null && _sessionId != null) {
      await loadForSession(
        campaignId: _campaignId!,
        sessionId: _sessionId!,
      );
    }
  }

  Future<void> _restoreContextFromCampaignSyncId(String campaignSyncId) async {
    final syncId = campaignSyncId.trim();
    if (syncId.isEmpty) return;
    final campaign = await _campaignRepository.getBySyncId(syncId);
    if (campaign?.id != null) _campaignId = campaign!.id;
  }

  Future<void> _restoreContextFromBattleEvent(dynamic rawBattle) async {
    if (rawBattle is! Map) return;
    final campaignSyncId =
        rawBattle['campaign_sync_id']?.toString().trim() ?? '';
    final sessionSyncId =
        rawBattle['session_sync_id']?.toString().trim() ?? '';

    if (campaignSyncId.isNotEmpty) {
      final campaign = await _campaignRepository.getBySyncId(campaignSyncId);
      if (campaign?.id != null) _campaignId = campaign!.id;
    }
    if (sessionSyncId.isNotEmpty) {
      final session = await _sessionRepository.getBySyncId(sessionSyncId);
      if (session?.id != null) {
        _sessionId = session!.id;
        _campaignId ??= session.campaignId;
      }
    }
  }

  Future<void> _appendLocalJournal(
    String battleSyncId, {
    required String type,
    String actorCharacterSyncId = '',
    String targetCharacterSyncId = '',
    String targetLabel = '',
    String actionSyncId = '',
    String actionRequestSyncId = '',
    int? amount,
    int? turnSequence,
    Map<String, dynamic> metadata = const {},
  }) async {
    final entry = BattleLogEntryModel(
      syncId: SyncIds.newId(),
      battleSyncId: battleSyncId,
      type: type,
      actorCharacterSyncId: actorCharacterSyncId,
      targetCharacterSyncId: targetCharacterSyncId,
      targetLabel: targetLabel,
      actionSyncId: actionSyncId,
      actionRequestSyncId: actionRequestSyncId,
      amount: amount,
      turnSequence: turnSequence,
      metadata: metadata,
      createdAt: DateTime.now(),
    );
    final id = await _logRepository.create(entry);
    _journal = [..._journal, entry.copyWith(id: id)];
    if (_journal.length > 100) {
      _journal = _journal.sublist(_journal.length - 100);
    }
  }

  void _updateProjections(dynamic raw) {
    if (raw is! List) return;
    _projections.clear();
    for (final value in raw) {
      if (value is Map) {
        final projection = BattleProjectionModel.fromMap(
          value.map((key, value) => MapEntry(key.toString(), value)),
        );
        if (projection.characterSyncId.isNotEmpty) {
          _projections[projection.characterSyncId] = projection;
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}

class DiceDisplay {
  final String expression;
  final List<int> rolls;
  final int modifier;
  final int total;

  const DiceDisplay({
    required this.expression,
    required this.rolls,
    required this.modifier,
    required this.total,
  });
}
