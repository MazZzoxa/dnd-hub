import '../database/database_helper.dart';
import '../models/note_model.dart';

class NoteRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<NoteModel>> getForCharacter(int characterId) async {
    final db = await _db.database;
    final rows = await db.query(
      'notes',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'created_at DESC',
    );
    return rows.map(NoteModel.fromMap).toList();
  }

  Future<int> create(NoteModel note) async {
    final db = await _db.database;
    return db.insert('notes', note.toMap());
  }

  Future<int> update(NoteModel note) async {
    final db = await _db.database;
    return db.update('notes', note.toMap(), where: 'id = ?', whereArgs: [note.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }
}
