import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/spell_slot_model.dart';

class SpellSlotRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<SpellSlotModel>> getForCharacter(int characterId) async {
    final db = await _db.database;
    final rows = await db.query(
      'spell_slots',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'level',
    );
    return rows.map(SpellSlotModel.fromMap).toList();
  }

  /// Создаёт или обновляет запись об ячейках для данного уровня
  /// (character_id, level) — составной первичный ключ.
  Future<void> upsert(SpellSlotModel slot) async {
    final db = await _db.database;
    await db.insert(
      'spell_slots',
      slot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
