import '../database/database_helper.dart';
import '../models/battle_turn_model.dart';
import '../../network/services/sync_ids.dart';

class BattleTurnRepository {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<List<BattleTurnModel>> getForBattle(String battleSyncId) async {
    final db = await _database.database;
    final rows = await db.query(
      'battle_turns',
      where: 'battle_sync_id = ?',
      whereArgs: [battleSyncId],
      orderBy: 'sequence ASC, id ASC',
    );
    return rows.map(BattleTurnModel.fromMap).toList();
  }

  Future<BattleTurnModel?> getActive(String battleSyncId) async {
    final db = await _database.database;
    final rows = await db.query(
      'battle_turns',
      where: "battle_sync_id = ? AND status = 'active'",
      whereArgs: [battleSyncId],
      orderBy: 'sequence DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : BattleTurnModel.fromMap(rows.first);
  }

  Future<int> create(BattleTurnModel turn) async {
    final db = await _database.database;
    final map = turn.toMap()..remove('id');
    map['sync_id'] = turn.syncId.isEmpty ? SyncIds.newId() : turn.syncId;
    return db.insert('battle_turns', map);
  }

  Future<void> update(BattleTurnModel turn) async {
    final db = await _database.database;
    await db.update(
      'battle_turns',
      turn.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [turn.id],
    );
  }
}
