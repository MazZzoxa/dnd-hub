import '../database/database_helper.dart';
import '../models/battle_model.dart';
import '../../network/services/sync_ids.dart';

class BattleRepository {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<List<BattleModel>> getForSession(int sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      'battles',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy:
          "CASE status WHEN 'active' THEN 0 ELSE 1 END, created_at DESC, id DESC",
    );
    return rows.map(BattleModel.fromMap).toList();
  }

  Future<BattleModel?> getActive(int sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      'battles',
      where: "session_id = ? AND status = 'active'",
      whereArgs: [sessionId],
      orderBy: 'started_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : BattleModel.fromMap(rows.first);
  }

  Future<BattleModel?> getActiveForCampaign(int campaignId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT b.* FROM battles b '
      'JOIN campaign_sessions s ON s.id = b.session_id '
      'WHERE s.campaign_id = ? AND b.status = \'active\' '
      'ORDER BY b.started_at DESC, b.id DESC LIMIT 1',
      [campaignId],
    );
    return rows.isEmpty ? null : BattleModel.fromMap(rows.first);
  }

  Future<int> create(BattleModel battle) async {
    final db = await _database.database;
    final map = battle.toMap()..remove('id');
    map['sync_id'] = battle.syncId.isEmpty ? SyncIds.newId() : battle.syncId;
    return db.insert('battles', map);
  }

  Future<void> update(BattleModel battle) async {
    final db = await _database.database;
    await db.update(
      'battles',
      battle.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [battle.id],
    );
  }
}
