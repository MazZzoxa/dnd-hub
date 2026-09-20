import '../database/database_helper.dart';
import '../models/attack_model.dart';
import '../../network/services/sync_ids.dart';

class AttackRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<AttackModel>> getForCharacter(int characterId) async {
    final db = await _db.database;
    final rows = await db.query(
      'attacks',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'sort_order, id',
    );
    return rows.map(AttackModel.fromMap).toList();
  }

  Future<int> create(AttackModel attack) async {
    final db = await _db.database;
    final map = attack.toMap();
    map['sync_id'] = attack.syncId.isEmpty ? SyncIds.newId() : attack.syncId;
    return db.insert('attacks', map);
  }

  Future<int> update(AttackModel attack) async {
    final db = await _db.database;
    return db.update('attacks', attack.toMap(), where: 'id = ?', whereArgs: [attack.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('attacks', where: 'id = ?', whereArgs: [id]);
  }
}
