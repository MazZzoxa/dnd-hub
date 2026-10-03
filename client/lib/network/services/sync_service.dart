import 'dart:async';

import '../../data/models/character_model.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/ability_model.dart';
import '../../data/models/custom_action_model.dart';
import '../../data/models/attack_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/spell_model.dart';
import '../../data/repositories/ability_repository.dart';
import '../../data/repositories/character_repository.dart';
import '../../data/repositories/attack_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/custom_action_repository.dart';
import '../../data/repositories/spell_repository.dart';
import '../connection_manager.dart';
import '../protocol/network_message.dart';
import 'local_sync_store.dart';

class SyncService {
  final ConnectionManager connectionManager;
  final LocalSyncStore store;
  StreamSubscription<String>? _messages;
  StreamSubscription<dynamic>? _connectionStates;
  final StreamController<NetworkMessage> _events = StreamController.broadcast();
  Future<void> _messageQueue = Future<void>.value();

  bool _publishingSnapshot = false;
  final Map<String, Completer<NetworkMessage>> _pendingAcks = {};
  final Map<String, NetworkMessage> _recentCommandResponses = {};

  SyncService(this.connectionManager, {LocalSyncStore? store})
      : store = store ?? LocalSyncStore() {
    _messages = connectionManager.messageStream.listen(_onMessage);
    _connectionStates = connectionManager.stateStream.listen(_onConnectionState);
  }

  Stream<NetworkMessage> get events => _events.stream;
  bool get connected => connectionManager.connected;
  String get clientId => connectionManager.clientId;
  String get role => connectionManager.role;

  Future<void> publishCharacter(CharacterModel character) async {
    await publishEntity('character', character.toMap());
  }

  Future<void> publishEntity(String entity, Map<String, dynamic> data) async {
    if (!connected) return;
    try {
      final prepared = await store.preparePayload(entity, data);
      if (!await store.isPayloadInCampaign(entity, prepared, connectionManager.campaignId)) return;
      await connectionManager.sendCommand(
        'state.upsert',
        payload: {'entity': entity, 'data': prepared},
      );
    } catch (_) {
      // Local UI operations must not fail merely because a network packet
      // could not be produced.
    }
  }

  Future<void> linkOwnCharacter({required CampaignMemberModel member, required CharacterModel character}) async {
    if (!connected || member.syncId.isEmpty || member.clientId != clientId) return;

    // Send the character and its complete combat loadout together with the
    // link operation. This makes the initial GM view independent from the
    // ordering/timing of follow-up state events.
    final preparedCharacter = await store.preparePayload(
      'character',
      character.toMap(),
    );
    final loadout = await _buildCharacterLoadout(character);

    await _sendAndWaitForAck(
      'member.link_character',
      payload: {
        'member_sync_id': member.syncId,
        'character': preparedCharacter,
        'loadout': loadout,
      },
    );
  }

  Future<List<Map<String, dynamic>>> _buildCharacterLoadout(
    CharacterModel character,
  ) async {
    if (character.id == null || character.syncId.isEmpty) return const [];

    final results = await Future.wait([
      AttackRepository().getForCharacter(character.id!),
      SpellRepository().getForCharacter(character.id!),
      AbilityRepository().getForCharacter(character.id!),
      InventoryRepository().getForCharacter(character.id!),
      CustomActionRepository().getForCharacter(character.id!),
    ]);

    final attacks = results[0] as List<AttackModel>;
    final spells = results[1] as List<SpellModel>;
    final abilities = results[2] as List<AbilityModel>;
    final items = results[3] as List<ItemModel>;
    final customActions = results[4] as List<CustomActionModel>;

    final entities = <Map<String, dynamic>>[];
    Future<void> add(String entity, Map<String, dynamic> data) async {
      entities.add({
        'entity': entity,
        'data': await store.preparePayload(entity, data),
      });
    }

    for (final attack in attacks) await add('attack', attack.toMap());
    for (final spell in spells) await add('spell', spell.toMap());
    for (final ability in abilities) await add('ability', ability.toMap());
    for (final item in items) await add('item', item.toMap());
    for (final action in customActions) {
      await add('custom_action', action.toMap());
    }
    return entities;
  }

  /// Publishes the complete combat loadout for a character in one atomic
  /// network command. The server validates that the character belongs to the
  /// sending player, so this does not depend on the GM device having local
  /// copies of the child rows beforehand.
  Future<void> publishCharacterLoadout(CharacterModel character) async {
    if (!connected || character.id == null || character.syncId.isEmpty) return;
    final entities = await _buildCharacterLoadout(character);
    await _sendAndWaitForAck(
      'character.loadout.publish',
      payload: {
        'character_sync_id': character.syncId,
        'entities': entities,
      },
    );
  }

  Future<List<Map<String, dynamic>>?> requestCharacterLoadout({
    required String characterSyncId,
  }) async {
    if (!connected || characterSyncId.trim().isEmpty) return null;

    Future<List<Map<String, dynamic>>?> requestOnce() async {
      final response = await _sendAndWaitForAck(
        'character.loadout.request',
        payload: {'character_sync_id': characterSyncId.trim()},
      );
      final rawLoadout = response.payload['loadout'];
      if (rawLoadout is! List) return null;

      final result = <Map<String, dynamic>>[];
      for (final rawItem in rawLoadout) {
        if (rawItem is! Map) continue;
        final entity = rawItem['entity']?.toString() ?? '';
        final data = rawItem['data'];
        if (entity.isEmpty || data is! Map) continue;
        final normalized = data.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        result.add({
          'entity': entity,
          'data': normalized,
        });
        try {
          await store.applyEntity(entity, normalized);
        } catch (_) {
          // The UI can still use the authoritative payload directly even when
          // a local cache write is unavailable.
        }
      }
      return result;
    }

    final first = await requestOnce();
    if (first == null || first.isNotEmpty || connectionManager.role != 'gm') {
      return first;
    }

    // A GM request can legitimately race the player's first loadout publish.
    // The server asks the online owner to republish on an empty response, so
    // retry briefly before returning the empty authoritative state.
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final retry = await requestOnce();
      if (retry == null || retry.isNotEmpty) return retry;
    }
    return first;
  }

  Future<void> unlinkOwnCharacter({required CampaignMemberModel member}) async {
    if (!connected) throw StateError('Нет подключения к LAN-кампании.');
    if (member.clientId != clientId || member.role != CampaignRole.player) {
      throw StateError('Только подключённый игрок может отвязать своего персонажа.');
    }
    if (member.syncId.isEmpty) {
      throw StateError('У участника нет sync_id.');
    }
    if (member.linkedCharacterId == null) {
      return;
    }

    String? commandId;
    final completer = Completer<void>();
    late StreamSubscription<NetworkMessage> subscription;
    subscription = events.listen((event) {
      final eventName = event.payload['event']?.toString();
      if (commandId == null || event.payload['command_id']?.toString() != commandId) return;
      if (eventName == 'ack' && event.payload['unlinked'] == true) {
        if (!completer.isCompleted) completer.complete();
      } else if (eventName == 'error' && !completer.isCompleted) {
        completer.completeError(
          StateError(event.payload['message']?.toString() ?? 'Не удалось отвязать персонажа.'),
        );
      }
    });

    try {
      commandId = await connectionManager.sendCommand(
        'member.unlink_character',
        payload: {'member_sync_id': member.syncId},
      );
      if (commandId == null) throw StateError('Не удалось отправить запрос на отвязку.');
      await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> leaveCampaign({required CampaignMemberModel member}) async {
    if (!connected) throw StateError('Нет подключения к LAN-кампании.');
    if (member.clientId != clientId || member.role != CampaignRole.player) {
      throw StateError('Только подключённый игрок может покинуть эту кампанию.');
    }
    if (member.syncId.isEmpty) {
      throw StateError('У участника нет sync_id.');
    }

    String? commandId;
    final completer = Completer<void>();
    late StreamSubscription<NetworkMessage> subscription;
    subscription = events.listen((event) {
      final eventName = event.payload['event']?.toString();
      if (commandId == null || event.payload['command_id']?.toString() != commandId) return;
      if (eventName == 'ack' && event.payload['left'] == true) {
        if (!completer.isCompleted) completer.complete();
      } else if (eventName == 'error' && !completer.isCompleted) {
        completer.completeError(
          StateError(event.payload['message']?.toString() ?? 'Не удалось покинуть кампанию.'),
        );
      }
    });

    try {
      commandId = await connectionManager.sendCommand(
        'member.leave',
        payload: {'member_sync_id': member.syncId},
      );
      if (commandId == null) throw StateError('Не удалось отправить запрос на выход.');
      await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> publishDelete(String entity, String syncId) async {
    if (!connected || syncId.isEmpty) return;
    await connectionManager.sendCommand(
      'state.delete',
      payload: {'entity': entity, 'sync_id': syncId},
    );
  }

  Future<void> publishCampaignSnapshot(String campaignSyncId) async {
    if (!connected ||
        campaignSyncId.isEmpty ||
        campaignSyncId != connectionManager.campaignId ||
        _publishingSnapshot) return;
    _publishingSnapshot = true;
    try {
      final entities = await store.exportCampaignSnapshot(campaignSyncId);
      await connectionManager.sendCommand(
        'snapshot.publish',
        payload: {'entities': entities},
      );
    } catch (_) {
      // Snapshot is best-effort; ordinary entity events remain usable.
    } finally {
      _publishingSnapshot = false;
    }
  }

  Future<void> grantSessionXp({
    required String sessionSyncId,
    required String characterSyncId,
    required int amount,
    String reason = '',
  }) async {
    final response = await _sendAndWaitForAck(
      'character.xp.grant',
      payload: {
        'session_sync_id': sessionSyncId,
        'character_sync_id': characterSyncId,
        'type': 'xp',
        'amount': amount,
        'reason': reason,
      },
    );

    // The server ACK carries the authoritative post-operation state so the
    // GM device does not have to rely on a later snapshot/reconnect to see
    // the new XP and level locally.
    final character = response.payload['character'];
    if (character is Map) {
      await store.applyEntity(
        'character',
        character.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    final reward = response.payload['reward'];
    if (reward is Map) {
      await store.applyEntity(
        'session_reward',
        reward.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    final transaction = response.payload['xp_transaction'];
    if (transaction is Map) {
      await store.applyEntity(
        'xp_transaction',
        transaction.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
  }

  Future<void> claimSessionLoot({
    required String lootSyncId,
    required String characterSyncId,
  }) async {
    await _sendAndWaitForAck(
      'session.loot.claim',
      payload: {
        'loot_sync_id': lootSyncId,
        'character_sync_id': characterSyncId,
      },
    );
  }

  Future<void> startBattle({
    required String sessionSyncId,
    String battleName = '',
  }) async {
    await _sendAndWaitForAck(
      'battle.start',
      payload: {
        'session_sync_id': sessionSyncId,
        'battle_name': battleName,
      },
    );
  }

  Future<void> endBattle({required String battleSyncId}) async {
    await _sendAndWaitForAck(
      'battle.end',
      payload: {'battle_sync_id': battleSyncId},
    );
  }

  Future<void> applyDamage({
    required String battleSyncId,
    required String characterSyncId,
    required int amount,
  }) async {
    await modifyCharacterHp(
      characterSyncId: characterSyncId,
      delta: -amount,
      battleSyncId: battleSyncId,
    );
  }

  Future<void> heal({
    required String battleSyncId,
    required String characterSyncId,
    required int amount,
  }) async {
    await modifyCharacterHp(
      characterSyncId: characterSyncId,
      delta: amount,
      battleSyncId: battleSyncId,
    );
  }

  Future<void> setTemporaryHp({
    required String battleSyncId,
    required String characterSyncId,
    required int amount,
  }) async {
    await setCharacterTemporaryHp(
      characterSyncId: characterSyncId,
      amount: amount,
      battleSyncId: battleSyncId,
    );
  }

  Future<void> modifyCharacterHp({
    required String characterSyncId,
    required int delta,
    String sessionSyncId = '',
    String battleSyncId = '',
  }) async {
    final response = await _sendAndWaitForAck('character.hp.modify', payload: {
      'character_sync_id': characterSyncId,
      'delta': delta,
      if (sessionSyncId.isNotEmpty) 'session_sync_id': sessionSyncId,
      if (battleSyncId.isNotEmpty) 'battle_sync_id': battleSyncId,
    });
    await _applyCharacterAck(response);
  }

  Future<void> setCharacterTemporaryHp({
    required String characterSyncId,
    required int amount,
    String sessionSyncId = '',
    String battleSyncId = '',
  }) async {
    final response = await _sendAndWaitForAck('character.temp_hp.set', payload: {
      'character_sync_id': characterSyncId,
      'amount': amount,
      if (sessionSyncId.isNotEmpty) 'session_sync_id': sessionSyncId,
      if (battleSyncId.isNotEmpty) 'battle_sync_id': battleSyncId,
    });
    await _applyCharacterAck(response);
  }

  Future<void> setCharacterLifeState({
    required String characterSyncId,
    required String lifeState,
    String sessionSyncId = '',
    String battleSyncId = '',
  }) async {
    final response = await _sendAndWaitForAck('character.life_state.set', payload: {
      'character_sync_id': characterSyncId,
      'life_state': lifeState,
      if (sessionSyncId.isNotEmpty) 'session_sync_id': sessionSyncId,
      if (battleSyncId.isNotEmpty) 'battle_sync_id': battleSyncId,
    });
    await _applyCharacterAck(response);
  }

  Future<void> grantCharacterCurrency({
    required String sessionSyncId,
    required String characterSyncId,
    required String currency,
    required int amount,
    String reason = '',
  }) async {
    final response = await _sendAndWaitForAck('character.currency.grant', payload: {
      'session_sync_id': sessionSyncId,
      'character_sync_id': characterSyncId,
      'currency': currency,
      'amount': amount,
      'reason': reason,
    });
    await _applyCharacterAck(response);
    await _applyAckEntity(response, 'session_reward', 'reward');
  }

  Future<void> grantCharacterInspiration({
    required String sessionSyncId,
    required String characterSyncId,
    String reason = '',
  }) async {
    final response = await _sendAndWaitForAck('character.inspiration.grant', payload: {
      'session_sync_id': sessionSyncId,
      'character_sync_id': characterSyncId,
      'reason': reason,
    });
    await _applyCharacterAck(response);
    await _applyAckEntity(response, 'session_reward', 'reward');
  }

  Future<void> applyCharacterCondition({
    required String characterSyncId,
    required String name,
    String description = '',
    String sourceCharacterSyncId = '',
    String sourceLabel = '',
    int durationRounds = 0,
    int? remainingRounds,
    String scope = 'character',
    String sessionSyncId = '',
    String battleSyncId = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    final response = await _sendAndWaitForAck('character.condition.apply', payload: {
      'character_sync_id': characterSyncId,
      'name': name,
      'description': description,
      'source_character_sync_id': sourceCharacterSyncId,
      'source_label': sourceLabel,
      'duration_rounds': durationRounds,
      'remaining_rounds': remainingRounds ?? durationRounds,
      'scope': scope,
      'metadata': metadata,
      if (sessionSyncId.isNotEmpty) 'session_sync_id': sessionSyncId,
      if (battleSyncId.isNotEmpty) 'battle_sync_id': battleSyncId,
    });
    await _applyAckEntity(response, 'character_condition', 'condition');
  }

  Future<void> removeCharacterCondition({
    required String conditionSyncId,
    String sessionSyncId = '',
    String battleSyncId = '',
  }) async {
    final response = await _sendAndWaitForAck('character.condition.remove', payload: {
      'condition_sync_id': conditionSyncId,
      if (sessionSyncId.isNotEmpty) 'session_sync_id': sessionSyncId,
      if (battleSyncId.isNotEmpty) 'battle_sync_id': battleSyncId,
    });
    await _applyAckEntity(response, 'character_condition', 'condition');
  }

  Future<void> _applyCharacterAck(NetworkMessage response) async {
    final character = response.payload['character'];
    if (character is Map) {
      await store.applyEntity('character', character.map((key, value) => MapEntry(key.toString(), value)));
    }
  }

  Future<void> _applyAckEntity(NetworkMessage response, String entity, String key) async {
    final data = response.payload[key];
    if (data is Map) {
      await store.applyEntity(entity, data.map((key, value) => MapEntry(key.toString(), value)));
    }
  }

  Future<void> startBattleTurn({
    required String battleSyncId,
    required String characterSyncId,
  }) async {
    await _sendAndWaitForAck(
      'battle.turn.start',
      payload: {
        'battle_sync_id': battleSyncId,
        'character_sync_id': characterSyncId,
      },
    );
  }

  Future<void> endBattleTurn({
    required String battleSyncId,
    String? turnSyncId,
  }) async {
    await _sendAndWaitForAck(
      'battle.turn.end',
      payload: {
        'battle_sync_id': battleSyncId,
        'turn_sync_id': turnSyncId,
      },
    );
  }

  Future<void> submitBattleAction(Map<String, dynamic> payload) async {
    await _sendAndWaitForAck('battle.action.submit', payload: payload);
  }

  Future<void> approveBattleAction({required String actionRequestSyncId, String note = ''}) async {
    await _sendAndWaitForAck(
      'battle.action.approve',
      payload: {
        'action_request_sync_id': actionRequestSyncId,
        'note': note,
      },
    );
  }

  Future<void> modifyBattleAction({
    required String actionRequestSyncId,
    required Map<String, dynamic> modifications,
    String note = '',
  }) async {
    await _sendAndWaitForAck(
      'battle.action.modify',
      payload: {
        'action_request_sync_id': actionRequestSyncId,
        'modifications': modifications,
        'note': note,
      },
    );
  }

  Future<void> rejectBattleAction({
    required String actionRequestSyncId,
    String reason = '',
  }) async {
    await _sendAndWaitForAck(
      'battle.action.reject',
      payload: {
        'action_request_sync_id': actionRequestSyncId,
        'reason': reason,
      },
    );
  }

  Future<NetworkMessage> _sendAndWaitForAck(
    String command, {
    required Map<String, dynamic> payload,
  }) async {
    final commandId = await connectionManager.sendCommand(
      command,
      payload: payload,
    );
    if (commandId == null) {
      throw StateError('Нет подключения к серверу ГМ.');
    }

    final recent = _recentCommandResponses.remove(commandId);
    if (recent != null) {
      if (recent.payload['event']?.toString() == 'error') {
        throw StateError(
          recent.payload['message']?.toString() ??
              'Сервер отклонил боевую команду.',
        );
      }
      return recent;
    }

    final completer = Completer<NetworkMessage>();
    _pendingAcks[commandId] = completer;
    try {
      final response = await completer.future.timeout(
        const Duration(seconds: 5),
      );
      if (response.payload['event']?.toString() == 'error') {
        throw StateError(
          response.payload['message']?.toString() ??
              'Сервер отклонил боевую команду.',
        );
      }
      return response;
    } finally {
      _pendingAcks.remove(commandId);
    }
  }

  Future<void> ping() async {
    await connectionManager.sendCommand('ping', payload: const {});
  }

  Future<void> _onConnectionState(dynamic state) async {
    if (!connectionManager.connected || !state.toString().endsWith('connected')) return;

    if (connectionManager.role == 'gm') {
      // The GM's local campaign is the initial authoritative snapshot for
      // the temporary LAN server.
      await publishCampaignSnapshot(connectionManager.campaignId);
      return;
    }

    if (connectionManager.role == 'player') {
      // Re-publish the linked character's complete loadout on reconnect.
      // This also fixes characters linked before the v1.0 loadout sync was
      // introduced, without requiring the player to reopen Battle Mode.
      try {
        final data = await store.findLinkedCharacterForClient(
          campaignSyncId: connectionManager.campaignId,
          clientId: connectionManager.clientId,
        );
        if (data != null) {
          final character = CharacterModel.fromMap(data);
          await publishCharacterLoadout(character);
        }
      } catch (_) {
        // Reconnect loadout publication is best-effort.
      }
    }
  }

  void _onMessage(String raw) {
    final next = _messageQueue.then((_) => _processMessage(raw));
    _messageQueue = next.catchError((_) {});
  }

  Future<void> _processMessage(String raw) async {
    try {
      final message = NetworkMessage.fromEncoded(raw);
      if (message.protocol != NetworkMessage.protocolVersion) return;
      final eventName = message.payload['event']?.toString();
      final commandId = message.payload['command_id']?.toString();
      if ((eventName == 'ack' || eventName == 'error') && commandId != null) {
        final pending = _pendingAcks[commandId];
        if (pending != null && !pending.isCompleted) {
          pending.complete(message);
        } else {
          _recentCommandResponses[commandId] = message;
          if (_recentCommandResponses.length > 64) {
            _recentCommandResponses.remove(_recentCommandResponses.keys.first);
          }
        }
      }

      if (eventName == 'battle.started' ||
          eventName == 'battle.state' ||
          eventName == 'battle.snapshot' ||
          eventName == 'battle.ended') {
        final battle = message.payload['battle'];
        if (battle is Map) {
          await store.applyEntity(
            'battle',
            battle.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
        final sessionEvent = message.payload['session_event'];
        if (sessionEvent is Map) {
          await store.applyEntity(
            'session_event',
            sessionEvent.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }

      final domainEntity = message.payload['entity']?.toString();
      final domainData = message.payload['data'];
      if (domainEntity != null && domainData is Map &&
          (eventName?.startsWith('battle.') ?? false)) {
        await store.applyEntity(
          domainEntity,
          domainData.map((key, value) => MapEntry(key.toString(), value)),
        );
      }

      final inlineJournal = message.payload['journal_entry'];
      if (inlineJournal is Map && (eventName?.startsWith('battle.') ?? false)) {
        await store.applyEntity(
          'battle_log_entry',
          inlineJournal.map((key, value) => MapEntry(key.toString(), value)),
        );
      }

      if (eventName == 'character.loadout.pull') {
        final characterSyncId = message.payload['character_sync_id']?.toString().trim() ?? '';
        if (characterSyncId.isNotEmpty && connectionManager.role == 'player') {
          try {
            final character = await CharacterRepository().findBySyncId(characterSyncId);
            if (character != null) {
              await publishCharacterLoadout(character);
            }
          } catch (_) {
            // A loadout refresh request is best-effort; normal local play
            // should continue even if the character cannot be read.
          }
        }
      }

      if (eventName == 'state.upsert') {
        final entity = message.payload['entity']?.toString() ?? '';
        final data = message.payload['data'];
        if (data is Map) {
          await store.applyEntity(
            entity,
            data.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } else if (eventName == 'state.delete') {
        final entity = message.payload['entity']?.toString() ?? '';
        final syncId = message.payload['sync_id']?.toString() ?? '';
        await store.deleteEntity(entity, syncId);
      } else if (eventName == 'state.snapshot') {
        final rawEntities = message.payload['entities'];
        if (rawEntities is List) {
          final campaignSyncId = message.campaignId.isNotEmpty
              ? message.campaignId
              : connectionManager.campaignId;
          final entities = [
            for (final rawEntity in rawEntities)
              if (rawEntity is Map)
                rawEntity.map((key, value) => MapEntry(key.toString(), value)),
          ];
          await store.applySnapshot(campaignSyncId, entities);
        }
      }

      if (!_events.isClosed) _events.add(message);
    } catch (_) {
      // Bad packets are ignored at the protocol boundary.
    }
  }

  Future<void> dispose() async {
    for (final completer in _pendingAcks.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('Сетевой сервис завершён.'));
      }
    }
    _pendingAcks.clear();
    _recentCommandResponses.clear();
    await _messages?.cancel();
    await _connectionStates?.cancel();
    await _events.close();
  }
}
