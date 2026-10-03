import '../database/database_helper.dart';
import '../models/item_model.dart';
import '../models/battle_log_entry_model.dart';
import '../models/battle_model.dart';
import '../models/session_event_model.dart';
import '../models/session_history_entry_model.dart';
import '../models/session_loot_model.dart';
import '../models/session_note_model.dart';
import '../models/session_reward_model.dart';
import '../models/xp_transaction_model.dart';
import '../../network/services/sync_ids.dart';
import '../../domain/xp/xp_level_table.dart';

class SessionWorkspaceRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<SessionNoteModel>> getNotes(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query(
      'session_notes',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(SessionNoteModel.fromMap).toList();
  }

  Future<int> createNote(SessionNoteModel note) async {
    final db = await _db.database;
    final map = note.toMap()..remove('id');
    map['sync_id'] = note.syncId.isEmpty ? SyncIds.newId() : note.syncId;
    return db.insert('session_notes', map);
  }

  Future<void> updateNote(SessionNoteModel note) async {
    final db = await _db.database;
    await db.update('session_notes', note.toMap()..remove('id'), where: 'id = ?', whereArgs: [note.id]);
  }

  Future<void> deleteNote(SessionNoteModel note) async {
    final db = await _db.database;
    await db.delete('session_notes', where: 'id = ?', whereArgs: [note.id]);
  }

  Future<List<SessionEventModel>> getEvents(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query(
      'session_events',
      where: "session_id = ? AND type = 'custom'",
      whereArgs: [sessionId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(SessionEventModel.fromMap).toList();
  }

  Future<List<SessionEventModel>> _getAllEvents(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query(
      'session_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(SessionEventModel.fromMap).toList();
  }

  Future<int> createEvent(SessionEventModel event) async {
    final db = await _db.database;
    final map = event.toMap()..remove('id');
    map['sync_id'] = event.syncId.isEmpty ? SyncIds.newId() : event.syncId;
    return db.insert('session_events', map);
  }

  Future<List<SessionRewardModel>> getRewards(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query(
      'session_rewards',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(SessionRewardModel.fromMap).toList();
  }

  Future<int> createReward(SessionRewardModel reward) async {
    final db = await _db.database;
    final map = reward.toMap()..remove('id');
    map['sync_id'] = reward.syncId.isEmpty ? SyncIds.newId() : reward.syncId;
    return db.insert('session_rewards', map);
  }

  Future<List<SessionLootModel>> getLoot(int sessionId) async {
    final db = await _db.database;
    final rows = await db.query(
      'session_loot',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(SessionLootModel.fromMap).toList();
  }

  Future<int> createLoot(SessionLootModel loot) async {
    final db = await _db.database;
    final map = loot.toMap()..remove('id');
    map['sync_id'] = loot.syncId.isEmpty ? SyncIds.newId() : loot.syncId;
    return db.insert('session_loot', map);
  }

  Future<void> updateLoot(SessionLootModel loot) async {
    final db = await _db.database;
    await db.update('session_loot', loot.toMap()..remove('id'), where: 'id = ?', whereArgs: [loot.id]);
  }

  Future<void> deleteLoot(SessionLootModel loot) async {
    final db = await _db.database;
    await db.delete('session_loot', where: 'id = ?', whereArgs: [loot.id]);
  }

  Future<List<SessionHistoryEntryModel>> getHistory(int sessionId) async {
    final db = await _db.database;
    const combatEventTypes = {
      'battle_started',
      'battle_finished',
      'turn_started',
      'turn_ended',
      'action_submitted',
      'action_approved',
      'action_modified',
      'action_rejected',
      'attack_roll',
      'damage_roll',
      'healing_roll',
      'damage_applied',
      'healing_applied',
      'temporary_hp_applied',
      'condition_applied',
      'condition_removed',
      'downed',
      'death',
      'revived',
      'life_state_changed',
    };
    final events = (await _getAllEvents(sessionId))
        .where((event) => !combatEventTypes.contains(event.type))
        .toList();

    final battleRows = await db.query(
      'battles',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'started_at ASC, created_at ASC, id ASC',
    );
    final battles = battleRows.map(BattleModel.fromMap).toList();

    final battleLogsBySyncId = <String, List<BattleLogEntryModel>>{};
    if (battles.isNotEmpty) {
      final ids = battles
          .map((battle) => battle.syncId.trim())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
      if (ids.isNotEmpty) {
        final placeholders = List.filled(ids.length, '?').join(',');
        final rows = await db.rawQuery(
          'SELECT * FROM battle_log_entries WHERE battle_sync_id IN ($placeholders) ORDER BY created_at ASC, id ASC',
          ids,
        );
        for (final row in rows) {
          final entry = _battleLogFromMap(row);
          battleLogsBySyncId.putIfAbsent(entry.battleSyncId, () => []).add(entry);
        }
      }
    }

    final entries = <SessionHistoryEntryModel>[
      ...events.map(SessionHistoryEntryModel.fromEvent),
      ...battles.map(
        (battle) => SessionHistoryEntryModel.fromBattleGroup(
          battle,
          battleLogsBySyncId[battle.syncId] ?? const [],
        ),
      ),
    ];
    entries.sort((a, b) {
      final time = a.createdAt.compareTo(b.createdAt);
      if (time != 0) return time;
      if (a.kind == 'battle' && b.kind != 'battle') return -1;
      if (a.kind != 'battle' && b.kind == 'battle') return 1;
      return a.type.compareTo(b.type);
    });
    return entries;
  }

  Future<SessionRewardModel> grantXpLocally({
    required int sessionId,
    required String characterSyncId,
    required int amount,
    required String reason,
    required String createdBy,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'XP должен быть положительным.');
    final db = await _db.database;
    return db.transaction((txn) async {
      final sessionRows = await txn.query('campaign_sessions', columns: const ['id', 'status'], where: 'id = ?', whereArgs: [sessionId], limit: 1);
      if (sessionRows.isEmpty) throw StateError('Сессия не найдена.');
      if (sessionRows.first['status'] == 'planned') throw StateError('XP нельзя выдавать до начала сессии.');
      final characterRows = await txn.query(
        'characters',
        columns: const ['id', 'sync_id', 'xp', 'level', 'name'],
        where: 'sync_id = ?',
        whereArgs: [characterSyncId],
        limit: 1,
      );
      if (characterRows.isEmpty) throw StateError('Персонаж не найден.');
      final campaignCharacterRows = await txn.rawQuery(
        '''
        SELECT c.id
        FROM characters c
        JOIN campaign_members m ON m.linked_character_id = c.id
        JOIN campaign_sessions s ON s.campaign_id = m.campaign_id
        WHERE s.id = ? AND c.sync_id = ?
        LIMIT 1
        ''',
        [sessionId, characterSyncId],
      );
      if (campaignCharacterRows.isEmpty) throw StateError('Персонаж не относится к кампании этой сессии.');
      final character = characterRows.first;
      final oldXp = (character['xp'] as int?) ?? 0;
      final newXp = (oldXp + amount).clamp(0, 1 << 30).toInt();
      if (newXp == oldXp) throw StateError('Опыт уже находится на максимальном значении.');
      final oldLevel = (character['level'] as int?) ?? 1;
      final newLevel = XpLevelTable.levelForXp(newXp);
      final now = DateTime.now();
      final reward = SessionRewardModel(
        syncId: SyncIds.newId(),
        sessionId: sessionId,
        characterSyncId: characterSyncId,
        type: 'xp',
        amount: newXp - oldXp,
        reason: reason.trim(),
        levelBefore: oldLevel,
        levelAfter: newLevel,
        createdAt: now,
        createdBy: createdBy,
      );
      await txn.update('characters', {'xp': newXp, 'level': newLevel}, where: 'id = ?', whereArgs: [character['id']]);
      await txn.insert('session_rewards', reward.toMap()..remove('id'));
      final transaction = XpTransactionModel(
        syncId: SyncIds.newId(),
        characterId: character['id'] as int,
        delta: reward.amount,
        xpBefore: oldXp,
        xpAfter: newXp,
        levelBefore: oldLevel,
        levelAfter: newLevel,
        reason: reason.trim(),
        createdAt: now,
      );
      await txn.insert('xp_transactions', transaction.toMap()..remove('id'));
      final event = SessionEventModel(
        syncId: SyncIds.newId(),
        sessionId: sessionId,
        type: 'reward_granted',
        title: '+${reward.amount} XP — ${character['name']?.toString() ?? 'Персонаж'}',
        description: reason.trim(),
        metadata: {
          'reward_sync_id': reward.syncId,
          'character_sync_id': characterSyncId,
          'amount': reward.amount,
          'level_before': oldLevel,
          'level_after': newLevel,
        },
        createdAt: now,
        createdBy: createdBy,
      );
      await txn.insert('session_events', event.toMap()..remove('id'));
      final inserted = await txn.query('session_rewards', where: 'sync_id = ?', whereArgs: [reward.syncId], limit: 1);
      return SessionRewardModel.fromMap(inserted.single);
    });
  }

  Future<SessionRewardModel> grantCurrencyLocally({
    required int sessionId,
    required String characterSyncId,
    required String currency,
    required int amount,
    required String reason,
    required String createdBy,
  }) async {
    const fields = {'copper', 'silver', 'electrum', 'gold', 'platinum'};
    final normalizedCurrency = currency.trim().toLowerCase();
    if (!fields.contains(normalizedCurrency)) throw StateError('Неизвестный тип валюты.');
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'Количество должно быть положительным.');
    final db = await _db.database;
    return db.transaction((txn) async {
      final sessionRows = await txn.query('campaign_sessions', columns: const ['id', 'status'], where: 'id = ?', whereArgs: [sessionId], limit: 1);
      if (sessionRows.isEmpty) throw StateError('Сессия не найдена.');
      if (sessionRows.first['status'] == 'planned') throw StateError('Награду нельзя выдавать до начала сессии.');
      final characterRows = await txn.query('characters', columns: ['id', 'sync_id', 'name', 'level', normalizedCurrency], where: 'sync_id = ?', whereArgs: [characterSyncId], limit: 1);
      if (characterRows.isEmpty) throw StateError('Персонаж не найден.');
      final linkedRows = await txn.rawQuery('''
        SELECT c.id FROM characters c
        JOIN campaign_members m ON m.linked_character_id = c.id
        JOIN campaign_sessions s ON s.campaign_id = m.campaign_id
        WHERE s.id = ? AND c.sync_id = ? LIMIT 1
      ''', [sessionId, characterSyncId]);
      if (linkedRows.isEmpty) throw StateError('Персонаж не относится к кампании этой сессии.');
      final oldAmount = (characterRows.first[normalizedCurrency] as num?)?.toInt() ?? 0;
      final newAmount = (oldAmount + amount).clamp(0, 1 << 30).toInt();
      final now = DateTime.now();
      final reward = SessionRewardModel(
        syncId: SyncIds.newId(), sessionId: sessionId, characterSyncId: characterSyncId,
        type: 'currency', currency: normalizedCurrency, amount: amount, reason: reason.trim(),
        levelBefore: (characterRows.first['level'] as int?) ?? 1,
        levelAfter: (characterRows.first['level'] as int?) ?? 1, createdAt: now, createdBy: createdBy,
      );
      await txn.update('characters', {normalizedCurrency: newAmount}, where: 'id = ?', whereArgs: [characterRows.first['id']]);
      await txn.insert('session_rewards', reward.toMap()..remove('id'));
      final event = SessionEventModel(
        syncId: SyncIds.newId(), sessionId: sessionId, type: 'currency_reward',
        title: '+$amount ${normalizedCurrency.toUpperCase()} — ${characterRows.first['name']?.toString() ?? 'Персонаж'}',
        description: reason.trim(),
        metadata: {'reward_sync_id': reward.syncId, 'character_sync_id': characterSyncId, 'currency': normalizedCurrency, 'amount': amount},
        createdAt: now, createdBy: createdBy,
      );
      await txn.insert('session_events', event.toMap()..remove('id'));
      final inserted = await txn.query('session_rewards', where: 'sync_id = ?', whereArgs: [reward.syncId], limit: 1);
      return SessionRewardModel.fromMap(inserted.single);
    });
  }

  Future<SessionRewardModel> grantInspirationLocally({
    required int sessionId,
    required String characterSyncId,
    required String reason,
    required String createdBy,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final sessionRows = await txn.query('campaign_sessions', columns: const ['id', 'status'], where: 'id = ?', whereArgs: [sessionId], limit: 1);
      if (sessionRows.isEmpty) throw StateError('Сессия не найдена.');
      if (sessionRows.first['status'] == 'planned') throw StateError('Награду нельзя выдавать до начала сессии.');
      final characterRows = await txn.query('characters', columns: const ['id', 'sync_id', 'name', 'inspiration'], where: 'sync_id = ?', whereArgs: [characterSyncId], limit: 1);
      if (characterRows.isEmpty) throw StateError('Персонаж не найден.');
      final linkedRows = await txn.rawQuery('''
        SELECT c.id FROM characters c
        JOIN campaign_members m ON m.linked_character_id = c.id
        JOIN campaign_sessions s ON s.campaign_id = m.campaign_id
        WHERE s.id = ? AND c.sync_id = ? LIMIT 1
      ''', [sessionId, characterSyncId]);
      if (linkedRows.isEmpty) throw StateError('Персонаж не относится к кампании этой сессии.');
      if ((characterRows.first['inspiration'] as num?)?.toInt() == 1) throw StateError('У персонажа уже есть вдохновение.');
      final now = DateTime.now();
      final reward = SessionRewardModel(
        syncId: SyncIds.newId(), sessionId: sessionId, characterSyncId: characterSyncId,
        type: 'inspiration', amount: 1, reason: reason.trim(), createdAt: now, createdBy: createdBy,
      );
      await txn.update('characters', {'inspiration': 1}, where: 'id = ?', whereArgs: [characterRows.first['id']]);
      await txn.insert('session_rewards', reward.toMap()..remove('id'));
      final event = SessionEventModel(
        syncId: SyncIds.newId(), sessionId: sessionId, type: 'inspiration_granted',
        title: 'Вдохновение — ${characterRows.first['name']?.toString() ?? 'Персонаж'}',
        description: reason.trim(),
        metadata: {'reward_sync_id': reward.syncId, 'character_sync_id': characterSyncId},
        createdAt: now, createdBy: createdBy,
      );
      await txn.insert('session_events', event.toMap()..remove('id'));
      final inserted = await txn.query('session_rewards', where: 'sync_id = ?', whereArgs: [reward.syncId], limit: 1);
      return SessionRewardModel.fromMap(inserted.single);
    });
  }

  Future<SessionLootModel> claimLootLocally({
    required String lootSyncId,
    required String characterSyncId,
    required String createdBy,
  }) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final lootRows = await txn.query('session_loot', where: 'sync_id = ?', whereArgs: [lootSyncId], limit: 1);
      if (lootRows.isEmpty) throw StateError('Добыча не найдена.');
      final loot = SessionLootModel.fromMap(lootRows.single);
      if (loot.status != 'available') throw StateError('Эта добыча уже распределена.');
      final characterRows = await txn.query(
        'characters',
        columns: const ['id', 'name'],
        where: 'sync_id = ?',
        whereArgs: [characterSyncId],
        limit: 1,
      );
      if (characterRows.isEmpty) throw StateError('Персонаж не найден.');
      final campaignCharacterRows = await txn.rawQuery(
        '''
        SELECT c.id
        FROM characters c
        JOIN campaign_members m ON m.linked_character_id = c.id
        JOIN campaign_sessions s ON s.campaign_id = m.campaign_id
        JOIN session_loot l ON l.session_id = s.id
        WHERE l.sync_id = ? AND c.sync_id = ?
        LIMIT 1
        ''',
        [lootSyncId, characterSyncId],
      );
      if (campaignCharacterRows.isEmpty) throw StateError('Персонаж не относится к кампании этой сессии.');
      final now = DateTime.now();
      final item = ItemModel(
        syncId: SyncIds.newId(),
        characterId: characterRows.single['id'] as int,
        name: loot.name,
        quantity: loot.quantity,
        category: 'Other',
        description: loot.description,
      );
      await txn.insert('items', item.toMap()..remove('id'));
      final updated = loot.copyWith(
        status: 'claimed',
        claimedByCharacterSyncId: characterSyncId,
        updatedAt: now,
      );
      await txn.update('session_loot', updated.toMap()..remove('id'), where: 'id = ?', whereArgs: [loot.id]);
      final event = SessionEventModel(
        syncId: SyncIds.newId(),
        sessionId: loot.sessionId,
        type: 'loot_claimed',
        title: '${loot.name} → ${characterRows.single['name']?.toString() ?? 'Персонаж'}',
        description: loot.source.isEmpty ? '' : 'Источник: ${loot.source}',
        metadata: {
          'loot_sync_id': loot.syncId,
          'character_sync_id': characterSyncId,
          'item_sync_id': item.syncId,
          'quantity': loot.quantity,
        },
        createdAt: now,
        createdBy: createdBy,
      );
      await txn.insert('session_events', event.toMap()..remove('id'));
      final rows = await txn.query('session_loot', where: 'sync_id = ?', whereArgs: [loot.syncId], limit: 1);
      return SessionLootModel.fromMap(rows.single);
    });
  }

  BattleLogEntryModel _battleLogFromMap(Map<String, dynamic> row) {
    final map = Map<String, dynamic>.from(row);
    return BattleLogEntryModel.fromMap(map);
  }
}
