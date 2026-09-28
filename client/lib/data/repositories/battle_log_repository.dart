import '../database/database_helper.dart';
import '../models/battle_log_entry_model.dart';
import '../../network/services/sync_ids.dart';

class BattleLogRepository {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<List<BattleLogEntryModel>> getRecentForBattle(
    String battleSyncId, {
    int limit = 100,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'battle_log_entries',
      where: 'battle_sync_id = ?',
      whereArgs: [battleSyncId],
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
    );
    return rows.map(BattleLogEntryModel.fromMap).toList().reversed.toList();
  }

  Future<int> create(BattleLogEntryModel entry) async {
    final db = await _database.database;
    final map = entry.toMap()..remove('id');
    map['sync_id'] = entry.syncId.isEmpty ? SyncIds.newId() : entry.syncId;
    return db.insert('battle_log_entries', map);
  }
}
