import '../database/database_helper.dart';

/// Personal battle notes stored only in this installation of D&D Hub.
/// The session key is the shared session sync ID, while ownerKey keeps GM
/// notes separate from each player's notes.
class BattleNotesRepository {
  Future<String> getNote({
    required String sessionKey,
    required String ownerKey,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query(
      'battle_notes',
      columns: const ['content'],
      where: 'session_key = ? AND owner_key = ?',
      whereArgs: [sessionKey, ownerKey],
      limit: 1,
    );
    return rows.isEmpty ? '' : rows.first['content']?.toString() ?? '';
  }

  Future<void> saveNote({
    required String sessionKey,
    required String ownerKey,
    required String content,
  }) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((transaction) async {
      final updated = await transaction.update(
        'battle_notes',
        {'content': content, 'updated_at': now},
        where: 'session_key = ? AND owner_key = ?',
        whereArgs: [sessionKey, ownerKey],
      );
      if (updated == 0) {
        await transaction.insert('battle_notes', {
          'session_key': sessionKey,
          'owner_key': ownerKey,
          'content': content,
          'updated_at': now,
        });
      }
    });
  }
}
