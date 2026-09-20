import '../../data/database/database_helper.dart';
import 'sync_ids.dart';

class ClientIdentity {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<String> getOrCreateClientId() async {
    final db = await _database.database;
    final rows = await db.query(
      'local_identity',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const ['client_id'],
      limit: 1,
    );
    String? existingId;
    if (rows.isNotEmpty) {
      final existing = rows.first['value']?.toString().trim() ?? '';
      if (existing.isNotEmpty) existingId = existing;
    }
    final id = existingId ?? SyncIds.newId();
    if (existingId == null) {
      await db.insert('local_identity', {'key': 'client_id', 'value': id});
    }
    // Existing local campaigns created before v0.5.1 had no device identity
    // attached to their GM member. Claim those local GM memberships once.
    await db.update(
      'campaign_members',
      {'client_id': id},
      where: "role = 'gm' AND (client_id = '' OR client_id IS NULL)",
    );
    return id;
  }
}
