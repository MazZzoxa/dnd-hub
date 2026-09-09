import '../database/database_helper.dart';
import '../models/spell_model.dart';

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
    return db.insert('spells', spell.toMap());
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
