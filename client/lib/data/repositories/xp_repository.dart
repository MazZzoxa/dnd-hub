import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/character_model.dart';
import '../models/xp_transaction_model.dart';

class XpRepository {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<List<XpTransactionModel>> getHistory(int characterId) async {
    final db = await _database.database;
    final rows = await db.query('xp_transactions', where: 'character_id = ?', whereArgs: [characterId], orderBy: 'created_at DESC, id DESC');
    return rows.map(XpTransactionModel.fromMap).toList();
  }

  Future<XpTransactionModel> changeXp({
    required int characterId,
    required int delta,
    required int newXp,
    required int newLevel,
    required int oldXp,
    required int oldLevel,
    required String reason,
  }) async {
    if (delta == 0) {
      throw ArgumentError.value(delta, 'delta', 'Изменение XP не может быть равно нулю.');
    }
    final db = await _database.database;
    final now = DateTime.now();
    return db.transaction((txn) async {
      final updated = await txn.update(
        'characters',
        {'xp': newXp, 'level': newLevel},
        where: 'id = ?',
        whereArgs: [characterId],
      );
      if (updated != 1) throw StateError('Персонаж $characterId не найден.');
      final row = XpTransactionModel(
        characterId: characterId,
        delta: delta,
        xpBefore: oldXp,
        xpAfter: newXp,
        levelBefore: oldLevel,
        levelAfter: newLevel,
        reason: reason.trim(),
        createdAt: now,
      );
      final id = await txn.insert('xp_transactions', row.toMap()..remove('id'));
      return XpTransactionModel.fromMap({...row.toMap(), 'id': id});
    });
  }

  Future<void> seedCharacterStateIfNeeded(CharacterModel character) async {
    // Existing v0.2 characters are already authoritative; no synthetic history is created.
    final db = await _database.database;
    await db.update(
      'characters',
      {'level': character.level, 'xp': character.xp},
      where: 'id = ?',
      whereArgs: [character.id],
    );
  }
}
