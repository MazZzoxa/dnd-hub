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
    'character',
    'item',
    'spell',
    'ability',
    'attack',
    'note',
    'spell_slot',
    'xp_transaction',
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
        return data['campaign_sync_id']?.toString() == campaignSyncId;
      case 'character':
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
        'campaign_member' => 2,
        'session' => 2,
        _ => 3,
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
        await _upsert(db, 'campaigns', data);
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
        'character' => 'characters',
        'item' => 'items',
        'spell' => 'spells',
        'ability' => 'abilities',
        'attack' => 'attacks',
        'note' => 'notes',
        'spell_slot' => 'spell_slots',
        'xp_transaction' => 'xp_transactions',
        _ => throw ArgumentError('Unknown sync entity: $entity'),
      };
}
