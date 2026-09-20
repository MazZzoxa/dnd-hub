import '../database/database_helper.dart';
import '../models/character_model.dart';
import '../../network/services/sync_ids.dart';

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
    return db.insert('characters', {
      ...character.toMap(),
      'sync_id': character.syncId.isEmpty ? SyncIds.newId() : character.syncId,
    });
  }

  Future<CharacterModel?> findBySyncId(String syncId) async {
    final db = await _db.database;
    final rows = await db.query('characters', where: 'sync_id = ?', whereArgs: [syncId], limit: 1);
    return rows.isEmpty ? null : CharacterModel.fromMap(rows.first);
  }

  Future<int> upsertBySyncId(CharacterModel character) async {
    final db = await _db.database;
    final rows = await db.query('characters', where: 'sync_id = ?', whereArgs: [character.syncId], limit: 1);
    if (rows.isEmpty) {
      return create(character);
    }
    final id = rows.first['id'] as int;
    await db.update('characters', {...character.toMap()..remove('id')}, where: 'id = ?', whereArgs: [id]);
    return id;
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
