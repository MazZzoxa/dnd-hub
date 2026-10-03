import 'dart:convert';

import '../../data/database/database_helper.dart';
import 'sync_ids.dart';

/// Maps local SQLite identity (integer IDs / foreign keys) to the
/// transport-independent sync_id identity used by v0.5 LAN sync.
///
/// The network never receives local database IDs. This is important because
/// two devices can legitimately have different SQLite primary keys for the
/// same campaign/character.
class LocalSyncStore {
  final DatabaseHelper _database = DatabaseHelper.instance;

  static const supportedEntities = <String>{
    'campaign',
    'campaign_member',
    'session',
    'battle',
    'battle_turn',
    'battle_action_request',
    'battle_log_entry',
    'character',
    'item',
    'spell',
    'ability',
    'attack',
    'note',
    'spell_slot',
    'xp_transaction',
    'session_note',
    'session_event',
    'session_reward',
    'session_loot',
    'custom_action',
    'character_condition',
  };

  String _requireSyncId(Map<String, dynamic> data) {
    final syncId = data['sync_id']?.toString().trim() ?? '';
    if (syncId.isEmpty) throw StateError('Sync entity has no sync_id.');
    return syncId;
  }

  /// Repairs legacy/in-memory characters that still carry an empty sync_id.
  /// The generated ID is persisted before the entity is sent over the network,
  /// so subsequent character updates keep the same network identity.
  Future<void> _ensureCharacterSyncId(Map<String, dynamic> data) async {
    final current = data['sync_id']?.toString().trim() ?? '';
    if (current.isNotEmpty) return;

    final localId = (data['id'] as num?)?.toInt();
    if (localId == null) {
      data['sync_id'] = SyncIds.newId();
      return;
    }

    final db = await _database.database;
    final rows = await db.query(
      'characters',
      columns: const ['sync_id'],
      where: 'id = ?',
      whereArgs: [localId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw StateError('Character $localId was not found.');
    }

    var syncId = rows.first['sync_id']?.toString().trim() ?? '';
    if (syncId.isEmpty) {
      syncId = SyncIds.newId();
      await db.update(
        'characters',
        {'sync_id': syncId},
        where: 'id = ?',
        whereArgs: [localId],
      );
    }
    data['sync_id'] = syncId;
  }

  Future<String> _characterSyncId(int characterId) async {
    final db = await _database.database;
    final rows = await db.query(
      'characters',
      columns: const ['sync_id'],
      where: 'id = ?',
      whereArgs: [characterId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Character $characterId was not found.');
    final syncId = rows.first['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) throw StateError('Character $characterId has no sync_id.');
    return syncId;
  }

  Future<String> _sessionSyncId(int sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      'campaign_sessions',
      columns: const ['sync_id'],
      where: 'id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Session $sessionId was not found.');
    final syncId = rows.first['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) throw StateError('Session $sessionId has no sync_id.');
    return syncId;
  }

  Future<Map<String, dynamic>?> findLinkedCharacterForClient({
    required String campaignSyncId,
    required String clientId,
  }) async {
    final campaignId = await _localIdBySync(
      await _database.database,
      'campaigns',
      campaignSyncId.trim(),
    );
    if (campaignId == null || clientId.trim().isEmpty) return null;
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT ch.*
      FROM campaign_members m
      JOIN characters ch ON ch.id = m.linked_character_id
      WHERE m.campaign_id = ? AND m.client_id = ? AND m.role = 'player'
        AND m.linked_character_id IS NOT NULL
      LIMIT 1
      ''',
      [campaignId, clientId.trim()],
    );
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<String> _campaignSyncId(int campaignId) async {
    final db = await _database.database;
    final rows = await db.query(
      'campaigns',
      columns: const ['sync_id'],
      where: 'id = ?',
      whereArgs: [campaignId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('Campaign $campaignId was not found.');
    final syncId = rows.first['sync_id']?.toString() ?? '';
    if (syncId.isEmpty) throw StateError('Campaign $campaignId has no sync_id.');
    return syncId;
  }

  Future<String?> dbCampaignByBattleSyncId(String battleSyncId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT c.sync_id FROM battles b JOIN campaigns c ON c.id = b.campaign_id WHERE b.sync_id = ? LIMIT 1',
      [battleSyncId],
    );
    return rows.isEmpty ? null : rows.first['sync_id']?.toString();
  }

  Future<Map<String, dynamic>> preparePayload(
    String entity,
    Map<String, dynamic> source,
  ) async {
    if (!supportedEntities.contains(entity)) {
      throw ArgumentError.value(entity, 'entity', 'Unsupported sync entity.');
    }
    final data = Map<String, dynamic>.from(source);
    if (entity == 'character') {
      await _ensureCharacterSyncId(data);
    }
    _requireSyncId(data);
    data.remove('id');

    switch (entity) {
      case 'campaign':
      case 'character':
        // bio_image is intentionally local-only: it is binary/base64 data and
        // is not part of the realtime event stream.
        data.remove('bio_image');
        break;
      case 'campaign_member':
        final campaignId = (data.remove('campaign_id') as num?)?.toInt();
        if (campaignId == null) throw StateError('Campaign member has no campaign_id.');
        data['campaign_sync_id'] = await _campaignSyncId(campaignId);
        final linkedCharacterId = (data.remove('linked_character_id') as num?)?.toInt();
        if (linkedCharacterId != null) {
          data['linked_character_sync_id'] = await _characterSyncId(linkedCharacterId);
        } else {
          data['linked_character_sync_id'] = null;
        }
        break;
      case 'session':
        final campaignId = (data.remove('campaign_id') as num?)?.toInt();
        if (campaignId == null) throw StateError('Session has no campaign_id.');
        data['campaign_sync_id'] = await _campaignSyncId(campaignId);
        break;
      case 'session_note':
      case 'session_event':
      case 'session_reward':
      case 'session_loot':
        final sessionId = (data.remove('session_id') as num?)?.toInt();
        if (sessionId == null) throw StateError('$entity has no session_id.');
        data['session_sync_id'] = await _sessionSyncId(sessionId);
        if (entity == 'session_reward') {
          final characterSyncId = data['character_sync_id']?.toString().trim() ?? '';
          if (characterSyncId.isEmpty) throw StateError('session_reward has no character_sync_id.');
          data['character_sync_id'] = characterSyncId;
        }
        break;
      case 'battle':
        final campaignId = (data.remove('campaign_id') as num?)?.toInt();
        if (campaignId == null) throw StateError('У боя отсутствует идентификатор кампании.');
        data['campaign_sync_id'] = await _campaignSyncId(campaignId);
        final sessionId = (data.remove('session_id') as num?)?.toInt();
        if (sessionId == null) throw StateError('У боя отсутствует идентификатор сессии.');
        data['session_sync_id'] = await _sessionSyncId(sessionId);
        break;
      case 'battle_turn':
      case 'battle_action_request':
      case 'battle_log_entry':
        final battleSyncId = data['battle_sync_id']?.toString().trim() ?? '';
        if (battleSyncId.isEmpty) throw StateError('$entity has no battle_sync_id.');
        final campaign = await dbCampaignByBattleSyncId(battleSyncId);
        if (campaign == null) throw StateError('$entity references an unknown battle.');
        data['battle_sync_id'] = battleSyncId;
        break;
      case 'custom_action':
        final characterId = (data.remove('character_id') as num?)?.toInt();
        if (characterId == null) throw StateError('custom_action has no character_id.');
        data['character_sync_id'] = await _characterSyncId(characterId);
        break;
      case 'character_condition':
        final characterSyncId = data['character_sync_id']?.toString().trim() ?? '';
        if (characterSyncId.isEmpty) throw StateError('character_condition has no character_sync_id.');
        data.remove('character_id');
        break;
      case 'item':
      case 'spell':
      case 'ability':
        final characterId = (data.remove('character_id') as num?)?.toInt();
        if (characterId == null) throw StateError('$entity has no character_id.');
        data['character_sync_id'] = await _characterSyncId(characterId);
        // library_item_id is local-only and can point to a different row on
        // another device. The actual source URL and content remain portable.
        data.remove('library_item_id');
        break;
      case 'attack':
      case 'note':
      case 'spell_slot':
      case 'xp_transaction':
        final characterId = (data.remove('character_id') as num?)?.toInt();
        if (characterId == null) throw StateError('$entity has no character_id.');
        data['character_sync_id'] = await _characterSyncId(characterId);
        break;
    }
    return data;
  }

  Future<bool> isPayloadInCampaign(
    String entity,
    Map<String, dynamic> data,
    String campaignSyncId,
  ) async {
    if (campaignSyncId.isEmpty) return false;
    switch (entity) {
      case 'campaign':
        return data['sync_id']?.toString() == campaignSyncId;
      case 'campaign_member':
      case 'session':
      case 'battle':
        return data['campaign_sync_id']?.toString() == campaignSyncId;
      case 'session_note':
      case 'session_event':
      case 'session_reward':
      case 'session_loot':
        final sessionSyncId = data['session_sync_id']?.toString() ?? '';
        if (sessionSyncId.isEmpty) return false;
        final db = await _database.database;
        final rows = await db.rawQuery(
          'SELECT s.sync_id FROM campaign_sessions s JOIN campaigns c ON c.id = s.campaign_id WHERE s.sync_id = ? AND c.sync_id = ? LIMIT 1',
          [sessionSyncId, campaignSyncId],
        );
        if (rows.isEmpty) return false;
        if (entity != 'session_reward') return true;
        final characterSyncId = data['character_sync_id']?.toString() ?? '';
        if (characterSyncId.isEmpty) return false;
        final characterRows = await db.rawQuery(
          '''
          SELECT m.id
          FROM campaign_members m
          JOIN campaigns c ON c.id = m.campaign_id
          JOIN characters ch ON ch.id = m.linked_character_id
          WHERE c.sync_id = ? AND ch.sync_id = ?
          LIMIT 1
          ''',
          [campaignSyncId, characterSyncId],
        );
        return characterRows.isNotEmpty;
      case 'battle_turn':
      case 'battle_action_request':
      case 'battle_log_entry':
        final battleSyncId = data['battle_sync_id']?.toString() ?? '';
        if (battleSyncId.isEmpty) return false;
        final db = await _database.database;
        final rows = await db.rawQuery(
          'SELECT b.sync_id FROM battles b JOIN campaigns c ON c.id = b.campaign_id WHERE b.sync_id = ? AND c.sync_id = ? LIMIT 1',
          [battleSyncId, campaignSyncId],
        );
        return rows.isNotEmpty;
      case 'character':
      case 'custom_action':
      case 'character_condition':
      case 'item':
      case 'spell':
      case 'ability':
      case 'attack':
      case 'note':
      case 'spell_slot':
      case 'xp_transaction':
        final characterSyncId = data['character_sync_id']?.toString() ??
            (entity == 'character' ? data['sync_id']?.toString() ?? '' : '');
        if (characterSyncId.isEmpty) return false;
        final db = await _database.database;
        final rows = await db.rawQuery("""
          SELECT m.id
          FROM campaign_members m
          JOIN campaigns c ON c.id = m.campaign_id
          JOIN characters ch ON ch.id = m.linked_character_id
          WHERE c.sync_id = ? AND ch.sync_id = ?
          LIMIT 1
        """, [campaignSyncId, characterSyncId]);
        return rows.isNotEmpty;
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> exportCampaignSnapshot(
    String campaignSyncId,
  ) async {
    final db = await _database.database;
    final campaignRows = await db.query(
      'campaigns',
      where: 'sync_id = ?',
      whereArgs: [campaignSyncId],
      limit: 1,
    );
    if (campaignRows.isEmpty) {
      throw StateError('Campaign $campaignSyncId was not found locally.');
    }
    final campaign = Map<String, dynamic>.from(campaignRows.first)..remove('id');
    campaign.remove('bio_image');

    final result = <Map<String, dynamic>>[
      {'entity': 'campaign', 'data': campaign},
    ];

    final campaignId = campaignRows.first['id'] as int;
    final memberRows = await db.query(
      'campaign_members',
      where: 'campaign_id = ?',
      whereArgs: [campaignId],
      orderBy: 'id',
    );

    final characterIds = <int>{};
    for (final row in memberRows) {
      final data = Map<String, dynamic>.from(row)..remove('id');
      data.remove('campaign_id');
      data['campaign_sync_id'] = campaignSyncId;
      final linked = row['linked_character_id'] as int?;
      if (linked != null) {
        characterIds.add(linked);
        data['linked_character_sync_id'] = await _characterSyncId(linked);
      } else {
        data['linked_character_sync_id'] = null;
      }
      result.add({'entity': 'campaign_member', 'data': data});
    }

    final sessionRows = await db.query(
      'campaign_sessions',
      where: 'campaign_id = ?',
      whereArgs: [campaignId],
      orderBy: 'id',
    );
    for (final row in sessionRows) {
      final data = Map<String, dynamic>.from(row)..remove('id');
      data.remove('campaign_id');
      data['campaign_sync_id'] = campaignSyncId;
      result.add({'entity': 'session', 'data': data});
    }

    final sessionSyncById = <int, String>{
      for (final row in sessionRows)
        if (row['id'] is int) row['id'] as int: row['sync_id']?.toString() ?? '',
    };
    final sessionSyncIds = <String>{
      for (final row in sessionRows)
        if ((row['sync_id']?.toString() ?? '').isNotEmpty) row['sync_id'].toString(),
    };
    if (sessionSyncIds.isNotEmpty) {
      final sessionPlaceholders = List.filled(sessionSyncIds.length, '?').join(',');
      for (final spec in [
        ('session_notes', 'session_note'),
        ('session_events', 'session_event'),
        ('session_rewards', 'session_reward'),
        ('session_loot', 'session_loot'),
      ]) {
        final rows = await db.query(
          spec.$1,
          where: 'session_id IN (SELECT id FROM campaign_sessions WHERE sync_id IN ($sessionPlaceholders))',
          whereArgs: sessionSyncIds.toList(),
          orderBy: 'created_at ASC, id ASC',
        );
        for (final row in rows) {
          final data = Map<String, dynamic>.from(row)..remove('id');
          data.remove('session_id');
          data['session_sync_id'] = row['session_id'] == null
              ? ''
              : sessionSyncById[row['session_id'] as int?] ?? '';
          result.add({'entity': spec.$2, 'data': data});
        }
      }
    }

    final battleRows = await db.query(
      'battles',
      where: 'campaign_id = ?',
      whereArgs: [campaignId],
      orderBy: 'id',
    );
    final battleSyncIds = <String>{};
    for (final row in battleRows) {
      final data = Map<String, dynamic>.from(row)..remove('id');
      data.remove('campaign_id');
      data.remove('session_id');
      data['campaign_sync_id'] = campaignSyncId;
      data['session_sync_id'] = sessionSyncById[row['session_id'] as int] ?? '';
      final battleSyncId = data['sync_id']?.toString() ?? '';
      if (battleSyncId.isNotEmpty) battleSyncIds.add(battleSyncId);
      result.add({'entity': 'battle', 'data': data});
    }

    if (battleSyncIds.isNotEmpty) {
      final battlePlaceholders = List.filled(battleSyncIds.length, '?').join(',');
      final workspaceSpecs = [
        ('battle_turns', 'battle_turn'),
        ('battle_action_requests', 'battle_action_request'),
        ('battle_log_entries', 'battle_log_entry'),
      ];
      for (final spec in workspaceSpecs) {
        final rows = await db.query(
          spec.$1,
          where: 'battle_sync_id IN ($battlePlaceholders)',
          whereArgs: battleSyncIds.toList(),
          orderBy: 'id ASC',
        );
        for (final row in rows) {
          final data = Map<String, dynamic>.from(row)..remove('id');
          result.add({'entity': spec.$2, 'data': data});
        }
      }
    }

    if (characterIds.isEmpty) return result;

    final placeholders = List.filled(characterIds.length, '?').join(',');
    final ids = characterIds.toList();
    final characterRows = await db.query(
      'characters',
      where: 'id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'id',
    );
    final scopedCharacterSyncIds = <String>{};
    for (final row in characterRows) {
      final data = Map<String, dynamic>.from(row)..remove('id');
      data.remove('bio_image');
      result.add({'entity': 'character', 'data': data});
      scopedCharacterSyncIds.add(data['sync_id']?.toString() ?? '');
    }

    Future<void> appendCharacterChildren(
      String table,
      String entity, {
      String? orderBy,
    }) async {
      final rows = await db.query(
        table,
        where: 'character_id IN ($placeholders)',
        whereArgs: ids,
        orderBy: orderBy,
      );
      for (final row in rows) {
        final data = Map<String, dynamic>.from(row)..remove('id');
        data.remove('character_id');
        data['character_sync_id'] = await _characterSyncId(row['character_id'] as int);
        if (entity == 'item' || entity == 'spell' || entity == 'ability') {
          data.remove('library_item_id');
        }
        result.add({'entity': entity, 'data': data});
      }
    }

    await appendCharacterChildren('items', 'item', orderBy: 'id');
    await appendCharacterChildren('spells', 'spell', orderBy: 'level, id');
    await appendCharacterChildren('abilities', 'ability', orderBy: 'sort_order, id');
    await appendCharacterChildren('attacks', 'attack', orderBy: 'sort_order, id');
    await appendCharacterChildren('notes', 'note', orderBy: 'created_at, id');
    await appendCharacterChildren('spell_slots', 'spell_slot', orderBy: 'level');
    await appendCharacterChildren('xp_transactions', 'xp_transaction', orderBy: 'created_at, id');
    await appendCharacterChildren('custom_actions', 'custom_action', orderBy: 'sort_order, id');
    await appendCharacterChildren('character_conditions', 'character_condition', orderBy: 'created_at, id');

    result.removeWhere((item) {
      final data = item['data'];
      if (data is! Map) return false;
      final characterSyncId = data['character_sync_id']?.toString();
      return characterSyncId != null && characterSyncId.isNotEmpty && !scopedCharacterSyncIds.contains(characterSyncId);
    });

    return result;
  }

  Future<void> applySnapshot(
    String campaignSyncId,
    List<Map<String, dynamic>> rawEntities,
  ) async {
    if (campaignSyncId.isEmpty) return;

    final entities = <Map<String, dynamic>>[];
    final present = <String, Set<String>>{};
    final linkedCharacterSyncIds = <String>{};
    for (final raw in rawEntities) {
      final entity = raw['entity']?.toString() ?? '';
      final rawData = raw['data'];
      if (!supportedEntities.contains(entity) || rawData is! Map) continue;
      final data = rawData.map((key, value) => MapEntry(key.toString(), value));
      final syncId = data['sync_id']?.toString() ?? '';
      if (syncId.isEmpty) continue;
      entities.add({'entity': entity, 'data': data});
      present.putIfAbsent(entity, () => <String>{}).add(syncId);
      if (entity == 'campaign_member') {
        final linked = data['linked_character_sync_id']?.toString() ?? '';
        if (linked.isNotEmpty) linkedCharacterSyncIds.add(linked);
      }
    }

    int priority(Map<String, dynamic> item) {
      return switch (item['entity']?.toString() ?? '') {
        'campaign' => 0,
        'character' => 1,
        'custom_action' => 2,
        'character_condition' => 2,
        'campaign_member' => 3,
        'session' => 2,
        'session_note' => 3,
        'session_event' => 4,
        'session_reward' => 5,
        'session_loot' => 6,
        'battle' => 7,
        'battle_turn' => 8,
        'battle_action_request' => 9,
        'battle_log_entry' => 10,
        _ => 11,
      };
    }
    entities.sort((a, b) => priority(a).compareTo(priority(b)));

    final db = await _database.database;
    await db.transaction((txn) async {
      for (final item in entities) {
        final entity = item['entity']?.toString() ?? '';
        final data = item['data'];
        if (data is! Map) continue;
        await _applyEntityOnDb(
          txn,
          entity,
          data.map((key, value) => MapEntry(key.toString(), value)),
        );
      }

      final campaignId = await _localIdBySync(txn, 'campaigns', campaignSyncId);
      if (campaignId == null) return;

      final memberRows = await txn.query(
        'campaign_members',
        columns: const ['sync_id'],
        where: 'campaign_id = ?',
        whereArgs: [campaignId],
      );
      final memberSyncIds = present['campaign_member'] ?? const <String>{};
      final staleMemberIds = [
        for (final row in memberRows)
          if (!memberSyncIds.contains(row['sync_id']?.toString() ?? '')) row['sync_id']?.toString() ?? '',
      ];
      for (final syncId in staleMemberIds) {
        await txn.delete('campaign_members', where: 'sync_id = ?', whereArgs: [syncId]);
      }

      final sessionSyncIds = present['session'] ?? const <String>{};
      await txn.delete(
        'campaign_sessions',
        where: 'campaign_id = ? AND sync_id NOT IN (${List.filled(sessionSyncIds.isEmpty ? 1 : sessionSyncIds.length, '?').join(',')})',
        whereArgs: [campaignId, ...(sessionSyncIds.isEmpty ? ['__none__'] : sessionSyncIds.toList())],
      );

      final scopedSessionIds = [
        for (final row in await txn.query('campaign_sessions', columns: const ['id'], where: 'campaign_id = ?', whereArgs: [campaignId]))
          row['id'] as int,
      ];
      for (final spec in [
        ('session_notes', 'session_note'),
        ('session_events', 'session_event'),
        ('session_rewards', 'session_reward'),
        ('session_loot', 'session_loot'),
      ]) {
        if (scopedSessionIds.isEmpty) continue;
        final sessionPlaceholders = List.filled(scopedSessionIds.length, '?').join(',');
        final syncIds = present[spec.$2] ?? const <String>{};
        final syncPlaceholders = List.filled(syncIds.isEmpty ? 1 : syncIds.length, '?').join(',');
        await txn.delete(
          spec.$1,
          where: 'session_id IN ($sessionPlaceholders) AND sync_id NOT IN ($syncPlaceholders)',
          whereArgs: [
            ...scopedSessionIds,
            ...(syncIds.isEmpty ? ['__none__'] : syncIds.toList()),
          ],
        );
      }

      final existingBattleRows = await txn.query(
        'battles',
        columns: const ['sync_id'],
        where: 'campaign_id = ?',
        whereArgs: [campaignId],
      );
      final previousBattleSyncIds = [
        for (final row in existingBattleRows) row['sync_id']?.toString() ?? '',
      ].where((id) => id.isNotEmpty).toList();
      final battleSyncIds = present['battle'] ?? const <String>{};
      await txn.delete(
        'battles',
        where: 'campaign_id = ? AND sync_id NOT IN (${List.filled(battleSyncIds.isEmpty ? 1 : battleSyncIds.length, '?').join(',')})',
        whereArgs: [campaignId, ...(battleSyncIds.isEmpty ? ['__none__'] : battleSyncIds.toList())],
      );

      for (final spec in [
        ('battle_turns', 'battle_turn'),
        ('battle_action_requests', 'battle_action_request'),
        ('battle_log_entries', 'battle_log_entry'),
      ]) {
        final syncIds = present[spec.$2] ?? const <String>{};
        final scopedBattleSyncIds = <String>{
          ...previousBattleSyncIds,
          ...battleSyncIds,
        }.where((id) => id.isNotEmpty).toList();
        if (scopedBattleSyncIds.isEmpty) {
          continue;
        }
        final battlePlaceholders = List.filled(scopedBattleSyncIds.length, '?').join(',');
        final syncPlaceholders = List.filled(syncIds.isEmpty ? 1 : syncIds.length, '?').join(',');
        await txn.delete(
          spec.$1,
          where: 'battle_sync_id IN ($battlePlaceholders) AND sync_id NOT IN ($syncPlaceholders)',
          whereArgs: [
            ...scopedBattleSyncIds,
            ...(syncIds.isEmpty ? ['__none__'] : syncIds.toList()),
          ],
        );
      }

      if (linkedCharacterSyncIds.isEmpty) return;
      final placeholders = List.filled(linkedCharacterSyncIds.length, '?').join(',');
      final linkedRows = await txn.query(
        'characters',
        columns: const ['id'],
        where: 'sync_id IN ($placeholders)',
        whereArgs: linkedCharacterSyncIds.toList(),
      );
      final characterIds = [
        for (final row in linkedRows) row['id'] as int,
      ];
      if (characterIds.isEmpty) return;

      for (final spec in [
        ('items', 'item'),
        ('spells', 'spell'),
        ('abilities', 'ability'),
        ('attacks', 'attack'),
        ('notes', 'note'),
        ('spell_slots', 'spell_slot'),
        ('xp_transactions', 'xp_transaction'),
        ('custom_actions', 'custom_action'),
        ('character_conditions', 'character_condition'),
      ]) {
        final syncIds = present[spec.$2] ?? const <String>{};
        final charPlaceholders = List.filled(characterIds.length, '?').join(',');
        final syncPlaceholders = List.filled(syncIds.isEmpty ? 1 : syncIds.length, '?').join(',');
        await txn.delete(
          spec.$1,
          where: 'character_id IN ($charPlaceholders) AND sync_id NOT IN ($syncPlaceholders)',
          whereArgs: [
            ...characterIds,
            ...(syncIds.isEmpty ? ['__none__'] : syncIds.toList()),
          ],
        );
      }
    });
  }

  Future<void> applyEntity(String entity, Map<String, dynamic> source) async {
    if (!supportedEntities.contains(entity)) return;
    final db = await _database.database;
    await db.transaction((txn) async {
      await _applyEntityOnDb(txn, entity, Map<String, dynamic>.from(source));
    });
  }

  Future<void> _applyEntityOnDb(
    dynamic db,
    String entity,
    Map<String, dynamic> source,
  ) async {
    if (!supportedEntities.contains(entity)) return;
    final data = Map<String, dynamic>.from(source);
    final syncId = _requireSyncId(data);

    switch (entity) {
      case 'campaign':
        await _upsertCampaign(db, data);
        return;
      case 'character':
        data.remove('id');
        final existing = await db.query(
          'characters',
          columns: const ['id', 'bio_image'],
          where: 'sync_id = ?',
          whereArgs: [syncId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          data['bio_image'] = existing.first['bio_image']?.toString() ?? '';
        } else {
          data['bio_image'] = '';
        }
        await _upsert(db, 'characters', data);
        return;
      case 'campaign_member':
        final campaignId = await _localIdBySync(
          db,
          'campaigns',
          data.remove('campaign_sync_id')?.toString(),
        );
        if (campaignId == null) return;
        final linkedSyncId = data.remove('linked_character_sync_id')?.toString();
        final linkedCharacterId = await _localIdBySync(db, 'characters', linkedSyncId);
        data['campaign_id'] = campaignId;
        data['linked_character_id'] = linkedCharacterId;
        await _upsert(db, 'campaign_members', data);
        return;
      case 'session':
        final campaignId = await _localIdBySync(
          db,
          'campaigns',
          data.remove('campaign_sync_id')?.toString(),
        );
        if (campaignId == null) return;
        data['campaign_id'] = campaignId;
        await _upsert(db, 'campaign_sessions', data);
        return;
      case 'session_note':
      case 'session_event':
      case 'session_reward':
      case 'session_loot':
        final sessionId = await _localIdBySync(
          db,
          'campaign_sessions',
          data.remove('session_sync_id')?.toString(),
        );
        if (sessionId == null) return;
        data['session_id'] = sessionId;
        if (entity == 'session_event') {
          final metadata = data['metadata'];
          if (metadata is Map) data['metadata'] = jsonEncode(metadata);
        }
        await _upsert(db, _tableFor(entity), data);
        return;
      case 'battle':
        final campaignId = await _localIdBySync(
          db,
          'campaigns',
          data.remove('campaign_sync_id')?.toString(),
        );
        final sessionId = await _localIdBySync(
          db,
          'campaign_sessions',
          data.remove('session_sync_id')?.toString(),
        );
        if (campaignId == null || sessionId == null) return;
        data['campaign_id'] = campaignId;
        data['session_id'] = sessionId;
        await _upsert(db, 'battles', data);
        return;
      case 'battle_turn':
        await _upsert(db, 'battle_turns', data);
        return;
      case 'battle_action_request':
      case 'battle_log_entry':
        final metadata = data['metadata'];
        if (metadata is Map) {
          data['metadata'] = jsonEncode(metadata);
        }
        await _upsert(db, _tableFor(entity), data);
        return;
      case 'custom_action':
        final characterId = await _localIdBySync(
          db,
          'characters',
          data.remove('character_sync_id')?.toString(),
        );
        if (characterId == null) return;
        data['character_id'] = characterId;
        await _upsert(db, _tableFor(entity), data);
        return;
      case 'character_condition':
        final characterSyncId = data['character_sync_id']?.toString().trim() ?? '';
        if (characterSyncId.isEmpty) return;
        final characterId = await _localIdBySync(
          db,
          'characters',
          characterSyncId,
        );
        if (characterId == null) return;
        data['character_id'] = characterId;
        final metadata = data['metadata'];
        if (metadata is Map) data['metadata'] = jsonEncode(metadata);
        await _upsert(db, _tableFor(entity), data);
        return;
      case 'item':
      case 'spell':
      case 'ability':
      case 'attack':
      case 'note':
      case 'spell_slot':
      case 'xp_transaction':
        final characterId = await _localIdBySync(
          db,
          'characters',
          data.remove('character_sync_id')?.toString(),
        );
        if (characterId == null) return;
        data['character_id'] = characterId;
        data.remove('library_item_id');
        if (entity == 'spell_slot') {
          await _upsertSpellSlot(db, data);
        } else {
          await _upsert(db, _tableFor(entity), data);
        }
        return;
    }
  }

  Future<void> deleteEntity(String entity, String syncId) async {
    if (!supportedEntities.contains(entity) || syncId.isEmpty) return;
    final db = await _database.database;
    await db.delete(
      _tableFor(entity),
      where: 'sync_id = ?',
      whereArgs: [syncId],
    );
  }

  Future<int?> _localIdBySync(
    dynamic db,
    String table,
    String? syncId,
  ) async {
    if (syncId == null || syncId.isEmpty) return null;
    final rows = await db.query(
      table,
      columns: const ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['id'] as int?;
  }

  Future<void> _upsertCampaign(dynamic db, Map<String, dynamic> data) async {
    final syncId = _requireSyncId(data);
    final values = Map<String, dynamic>.from(data)..remove('id');

    final existing = await db.query(
      'campaigns',
      columns: const ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'campaigns',
        values,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return;
    }

    // A previous LAN implementation could leave a local placeholder/copy of
    // the same campaign with a different sync_id. Adopt that row instead of
    // creating another visible campaign, but only when the identity is exact
    // and the local row has no session history and only the initial GM member.
    final name = values['name']?.toString() ?? '';
    final description = values['description']?.toString() ?? '';
    final createdAt = values['created_at']?.toString() ?? '';
    final candidates = await db.query(
      'campaigns',
      columns: const ['id', 'sync_id'],
      where: 'name = ? AND description = ? AND created_at = ? AND sync_id <> ?',
      whereArgs: [name, description, createdAt, syncId],
      orderBy: 'id',
    );

    for (final candidate in candidates) {
      final campaignId = candidate['id'] as int;
      final sessions = await db.query(
        'campaign_sessions',
        columns: const ['id'],
        where: 'campaign_id = ?',
        whereArgs: [campaignId],
        limit: 1,
      );
      if (sessions.isNotEmpty) continue;

      final members = await db.query(
        'campaign_members',
        columns: const ['id', 'role'],
        where: 'campaign_id = ?',
        whereArgs: [campaignId],
      );
      if (members.length > 1) continue;
      if (members.isNotEmpty && members.first['role']?.toString() != 'gm') continue;

      await db.update(
        'campaigns',
        values,
        where: 'id = ?',
        whereArgs: [campaignId],
      );
      return;
    }

    await db.insert('campaigns', values);
  }

  Future<void> _upsert(dynamic db, String table, Map<String, dynamic> data) async {
    final syncId = _requireSyncId(data);
    final existing = await db.query(
      table,
      columns: const ['id'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    final values = Map<String, dynamic>.from(data)..remove('id');
    if (existing.isEmpty) {
      await db.insert(table, values);
    } else {
      await db.update(table, values, where: 'id = ?', whereArgs: [existing.first['id']]);
    }
  }

  Future<void> _upsertSpellSlot(dynamic db, Map<String, dynamic> data) async {
    final syncId = _requireSyncId(data);
    final bySync = await db.query(
      'spell_slots',
      columns: const ['character_id', 'level'],
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    final values = Map<String, dynamic>.from(data);
    if (bySync.isNotEmpty) {
      await db.update(
        'spell_slots',
        values,
        where: 'character_id = ? AND level = ?',
        whereArgs: [bySync.first['character_id'], bySync.first['level']],
      );
      return;
    }
    final characterId = values['character_id'];
    final level = values['level'];
    final byKey = await db.query(
      'spell_slots',
      columns: const ['character_id', 'level'],
      where: 'character_id = ? AND level = ?',
      whereArgs: [characterId, level],
      limit: 1,
    );
    if (byKey.isNotEmpty) {
      await db.update(
        'spell_slots',
        values,
        where: 'character_id = ? AND level = ?',
        whereArgs: [characterId, level],
      );
      return;
    }
    await db.insert('spell_slots', values);
  }

  String _tableFor(String entity) => switch (entity) {
        'campaign' => 'campaigns',
        'campaign_member' => 'campaign_members',
        'session' => 'campaign_sessions',
        'session_note' => 'session_notes',
        'session_event' => 'session_events',
        'session_reward' => 'session_rewards',
        'session_loot' => 'session_loot',
        'battle' => 'battles',
        'battle_turn' => 'battle_turns',
        'battle_action_request' => 'battle_action_requests',
        'battle_log_entry' => 'battle_log_entries',
        'character' => 'characters',
        'item' => 'items',
        'spell' => 'spells',
        'ability' => 'abilities',
        'attack' => 'attacks',
        'note' => 'notes',
        'spell_slot' => 'spell_slots',
        'xp_transaction' => 'xp_transactions',
        'custom_action' => 'custom_actions',
        'character_condition' => 'character_conditions',
        _ => throw ArgumentError('Unknown sync entity: $entity'),
      };
}
