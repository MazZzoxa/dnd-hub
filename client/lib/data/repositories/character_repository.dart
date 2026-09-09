import '../database/database_helper.dart';
import '../models/character_model.dart';

class CharacterRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<CharacterModel>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('characters', orderBy: 'name COLLATE NOCASE');
    return rows.map(CharacterModel.fromMap).toList();
  }

  Future<CharacterModel?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('characters', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return CharacterModel.fromMap(rows.first);
  }

  Future<int> create(CharacterModel character) async {
    final db = await _db.database;
    return db.insert('characters', character.toMap());
  }

  Future<int> update(CharacterModel character) async {
    final db = await _db.database;
    return db.update(
      'characters',
      character.toMap(),
      where: 'id = ?',
      whereArgs: [character.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }
}
