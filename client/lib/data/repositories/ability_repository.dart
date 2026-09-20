import '../database/database_helper.dart';
import '../models/ability_model.dart';
import '../../network/services/sync_ids.dart';

class AbilityRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<AbilityModel>> getForCharacter(int characterId) async {
    final db = await _db.database;
    final rows = await db.query(
      'abilities',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'sort_order, name COLLATE NOCASE',
    );
    return rows.map(AbilityModel.fromMap).toList();
  }

  Future<int> create(AbilityModel ability) async {
    final db = await _db.database;
    final map = ability.toMap();
    map['sync_id'] = ability.syncId.isEmpty ? SyncIds.newId() : ability.syncId;
    return db.insert('abilities', map);
  }

  Future<int> update(AbilityModel ability) async {
    final db = await _db.database;
    return db.update('abilities', ability.toMap(), where: 'id = ?', whereArgs: [ability.id]);
  }

  Future<void> reorder(List<AbilityModel> abilities) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      for (var i = 0; i < abilities.length; i++) {
        final ability = abilities[i];
        await txn.update(
          'abilities',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [ability.id],
        );
      }
    });
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('abilities', where: 'id = ?', whereArgs: [id]);
  }
}
