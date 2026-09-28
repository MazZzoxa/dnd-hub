import '../database/database_helper.dart';
import '../models/battle_action_request_model.dart';
import '../../network/services/sync_ids.dart';

class BattleActionRequestRepository {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<List<BattleActionRequestModel>> getForBattle(String battleSyncId) async {
    final db = await _database.database;
    final rows = await db.query(
      'battle_action_requests',
      where: 'battle_sync_id = ?',
      whereArgs: [battleSyncId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(BattleActionRequestModel.fromMap).toList();
  }

  Future<List<BattleActionRequestModel>> getPending(String battleSyncId) async {
    final db = await _database.database;
    final rows = await db.query(
      'battle_action_requests',
      where: "battle_sync_id = ? AND status = 'pending_gm'",
      whereArgs: [battleSyncId],
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(BattleActionRequestModel.fromMap).toList();
  }

  Future<int> create(BattleActionRequestModel request) async {
    final db = await _database.database;
    final map = request.toMap()..remove('id');
    map['sync_id'] = request.syncId.isEmpty ? SyncIds.newId() : request.syncId;
    return db.insert('battle_action_requests', map);
  }

  Future<void> update(BattleActionRequestModel request) async {
    final db = await _database.database;
    await db.update(
      'battle_action_requests',
      request.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [request.id],
    );
  }
}
