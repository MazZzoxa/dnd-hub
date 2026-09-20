import '../database/database_helper.dart';
import '../models/session_model.dart';
import '../../network/services/sync_ids.dart';

class SessionRepository {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<List<SessionModel>> getForCampaign(int campaignId) async {
    final db = await _database.database;
    final rows = await db.query(
      'campaign_sessions',
      where: 'campaign_id = ?',
      whereArgs: [campaignId],
      orderBy: "CASE status WHEN 'active' THEN 0 WHEN 'planned' THEN 1 ELSE 2 END, created_at DESC, id DESC",
    );
    return rows.map(SessionModel.fromMap).toList();
  }

  Future<SessionModel?> getActive(int campaignId) async {
    final db = await _database.database;
    final rows = await db.query(
      'campaign_sessions',
      where: "campaign_id = ? AND status = 'active'",
      whereArgs: [campaignId],
      orderBy: 'started_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : SessionModel.fromMap(rows.first);
  }

  Future<int> create(SessionModel session) async {
    final db = await _database.database;
    final map = session.toMap()..remove('id');
    map['sync_id'] = session.syncId.isEmpty ? SyncIds.newId() : session.syncId;
    return db.insert('campaign_sessions', map);
  }

  Future<void> update(SessionModel session) async {
    final db = await _database.database;
    await db.update(
      'campaign_sessions',
      session.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  Future<void> delete(int id) async {
    final db = await _database.database;
    await db.delete('campaign_sessions', where: 'id = ?', whereArgs: [id]);
  }
}
