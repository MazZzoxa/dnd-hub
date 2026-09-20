import '../database/database_helper.dart';
import '../models/spell_model.dart';
import '../../network/services/sync_ids.dart';

class SpellRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<SpellModel>> getForCharacter(int characterId) async {
    final db = await _db.database;
    final rows = await db.query(
      'spells',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'level, name COLLATE NOCASE',
    );
    return rows.map(SpellModel.fromMap).toList();
  }

  Future<int> create(SpellModel spell) async {
    final db = await _db.database;
    final map = spell.toMap();
    map['sync_id'] = spell.syncId.isEmpty ? SyncIds.newId() : spell.syncId;
    return db.insert('spells', map);
  }

  Future<int> update(SpellModel spell) async {
    final db = await _db.database;
    return db.update('spells', spell.toMap(), where: 'id = ?', whereArgs: [spell.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('spells', where: 'id = ?', whereArgs: [id]);
  }
}
