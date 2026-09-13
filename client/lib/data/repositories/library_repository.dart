import '../database/database_helper.dart';
import '../models/library_item_model.dart';

/// Репозиторий для Local Content Library (см. docs/D&D Hub.md п.20-22).
///
/// В отличие от остальных репозиториев (InventoryRepository и т.д.), этот
/// не привязан к character_id — библиотека общая для всего приложения.
class LibraryRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<LibraryItemModel>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('library_items', orderBy: 'type, name COLLATE NOCASE');
    return rows.map(LibraryItemModel.fromMap).toList();
  }

  Future<List<LibraryItemModel>> getByType(LibraryItemType type) async {
    final db = await _db.database;
    final rows = await db.query(
      'library_items',
      where: 'type = ?',
      whereArgs: [type.dbValue],
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(LibraryItemModel.fromMap).toList();
  }

  Future<LibraryItemModel?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('library_items', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return LibraryItemModel.fromMap(rows.first);
  }

  /// Поиск по названию (см. п.23 ТЗ: "+ Add Item" -> Search / Library).
  /// Пустая строка [query] и не указанный [type] эквивалентны [getAll].
  Future<List<LibraryItemModel>> search(String query, {LibraryItemType? type}) async {
    final db = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (query.isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%$query%');
    }
    if (type != null) {
      where.add('type = ?');
      args.add(type.dbValue);
    }

    final rows = await db.query(
      'library_items',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: where.isEmpty ? null : args,
      orderBy: 'name COLLATE NOCASE',
    );
    return rows.map(LibraryItemModel.fromMap).toList();
  }

  Future<int> create(LibraryItemModel item) async {
    final db = await _db.database;
    return db.insert('library_items', item.toMap());
  }

  Future<int> update(LibraryItemModel item) async {
    final db = await _db.database;
    return db.update('library_items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }


  Future<void> deleteMany(Iterable<int> ids) async {
    final uniqueIds = ids.toSet().toList();
    if (uniqueIds.isEmpty) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in uniqueIds) {
        batch.delete('library_items', where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    return db.delete('library_items', where: 'id = ?', whereArgs: [id]);
  }
}
