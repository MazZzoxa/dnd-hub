import '../database/database_helper.dart';
import '../models/item_model.dart';
import '../../network/services/sync_ids.dart';

class InventoryRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<ItemModel>> getForCharacter(int characterId) async {
    final db = await _db.database;
    final rows = await db.query(
      'items',
      where: 'character_id = ?',
      whereArgs: [characterId],
      orderBy: 'category, name COLLATE NOCASE',
    );
    return rows.map(ItemModel.fromMap).toList();
  }

  Future<int> create(ItemModel item) async {
    final db = await _db.database;
    final map = item.toMap();
    map['sync_id'] = item.syncId.isEmpty ? SyncIds.newId() : item.syncId;
    return db.insert('items', map);
  }

  Future<int> update(ItemModel item) async {
    final db = await _db.database;
    return db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('items', where: 'id = ?', whereArgs: [id]);
  }
}
