
import '../database/database_helper.dart';
import '../models/character_condition_model.dart';
import '../../network/services/sync_ids.dart';

class CharacterConditionRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<CharacterConditionModel>> getForCharacter(int characterId, {bool activeOnly = true}) async {
    final db = await _db.database;
    final rows = await db.query(
      'character_conditions',
      where: activeOnly ? 'character_id = ? AND active = 1' : 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(CharacterConditionModel.fromMap).toList();
  }

  Future<int> create(CharacterConditionModel condition) async {
    final db = await _db.database;
    final map = condition.toMap()..remove('id');
    map['sync_id'] = condition.syncId.isEmpty ? SyncIds.newId() : condition.syncId;
    return db.insert('character_conditions', map);
  }

  Future<void> update(CharacterConditionModel condition) async {
    final db = await _db.database;
    await db.update('character_conditions', condition.toMap()..remove('id'), where: 'id = ?', whereArgs: [condition.id]);
  }

  Future<void> delete(CharacterConditionModel condition) async {
    final db = await _db.database;
    await db.delete('character_conditions', where: 'id = ?', whereArgs: [condition.id]);
  }

  Future<CharacterConditionModel?> findBySyncId(String syncId) async {
    final db = await _db.database;
    final rows = await db.query('character_conditions', where: 'sync_id = ?', whereArgs: [syncId], limit: 1);
    return rows.isEmpty ? null : CharacterConditionModel.fromMap(rows.first);
  }
}
