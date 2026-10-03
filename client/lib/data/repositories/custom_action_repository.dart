import '../database/database_helper.dart';
import '../models/custom_action_model.dart';
import '../../network/services/sync_ids.dart';

class CustomActionRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<CustomActionModel>> getForCharacter(int characterId) async {
    final db = await _db.database;
    final rows = await db.query(
      'custom_actions', where: 'character_id = ?', whereArgs: [characterId],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(CustomActionModel.fromMap).toList();
  }

  Future<int> create(CustomActionModel action) async {
    final db = await _db.database;
    final map = action.toMap()..remove('id');
    map['sync_id'] = action.syncId.isEmpty ? SyncIds.newId() : action.syncId;
    return db.insert('custom_actions', map);
  }

  Future<void> update(CustomActionModel action) async {
    final db = await _db.database;
    await db.update('custom_actions', action.toMap()..remove('id'), where: 'id = ?', whereArgs: [action.id]);
  }

  Future<void> delete(CustomActionModel action) async {
    final db = await _db.database;
    await db.delete('custom_actions', where: 'id = ?', whereArgs: [action.id]);
  }

  Future<CustomActionModel?> findBySyncId(String syncId) async {
    final db = await _db.database;
    final rows = await db.query('custom_actions', where: 'sync_id = ?', whereArgs: [syncId], limit: 1);
    return rows.isEmpty ? null : CustomActionModel.fromMap(rows.first);
  }
}
