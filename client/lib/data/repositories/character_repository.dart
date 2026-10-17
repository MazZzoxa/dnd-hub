import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/character_model.dart';
import '../../network/services/sync_ids.dart';
import 'bio_image_store.dart';

class CharacterRepository {
  final DatabaseHelper _db = DatabaseHelper.instance;

  /// Читает персонажей, никогда не вытаскивая гигантский `bio_image`
  /// (см. [BioImageStore]). В модели `bioImageBase64` — миниатюра/небольшая
  /// картинка; полное изображение запрашивается через [loadFullBioImage].
  Future<List<Map<String, Object?>>> _safeQuery(
    Database db, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    final columns = await BioImageStore.safeSelectList(db);
    final sql = StringBuffer('SELECT $columns FROM characters');
    if (where != null) sql.write(' WHERE $where');
    if (orderBy != null) sql.write(' ORDER BY $orderBy');
    if (limit != null) sql.write(' LIMIT $limit');
    return db.rawQuery(sql.toString(), whereArgs);
  }

  Future<List<CharacterModel>> getAll() async {
    final db = await _db.database;
    await BioImageStore.migrateOversized(db);
    final rows = await _safeQuery(db, orderBy: 'name COLLATE NOCASE');
    return rows.map(CharacterModel.fromMap).toList();
  }

  Future<CharacterModel?> getById(int id) async {
    final db = await _db.database;
    final rows = await _safeQuery(db, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return CharacterModel.fromMap(rows.first);
  }

  Future<int> create(CharacterModel character) async {
    final db = await _db.database;
    final id = await db.insert('characters', {
      ...character.toMap(),
      'sync_id': character.syncId.isEmpty ? SyncIds.newId() : character.syncId,
    });
    if (character.bioImageBase64.length > BioImageStore.inlineLimit) {
      await BioImageStore.migrateOversized(db);
    }
    return id;
  }

  Future<CharacterModel?> findBySyncId(String syncId) async {
    final db = await _db.database;
    final rows = await _safeQuery(
      db,
      where: 'sync_id = ?',
      whereArgs: [syncId],
      limit: 1,
    );
    return rows.isEmpty ? null : CharacterModel.fromMap(rows.first);
  }

  Future<int> upsertBySyncId(CharacterModel character) async {
    final db = await _db.database;
    final rows = await db.query(
      'characters',
      columns: const ['id'],
      where: 'sync_id = ?',
      whereArgs: [character.syncId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return create(character);
    }
    final id = rows.first['id'] as int;
    // Изображение не трогаем: им управляют setBioImage / clearBioImage.
    final map = character.toMap()
      ..remove('id')
      ..remove('bio_image');
    await db.update('characters', map, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<int> update(CharacterModel character) async {
    final db = await _db.database;
    // bio_image намеренно не перезаписывается обычным сохранением персонажа:
    // в модели хранится только миниатюра, а полное изображение лежит отдельно.
    final map = character.toMap()..remove('bio_image');
    return db.update(
      'characters',
      map,
      where: 'id = ?',
      whereArgs: [character.id],
    );
  }

  Future<int> delete(int id) async {
    final db = await _db.database;
    await BioImageStore.deleteImage(db, id);
    return db.delete('characters', where: 'id = ?', whereArgs: [id]);
  }

  // --- Изображение био ---

  /// Полное изображение (base64) без ограничения размера; '' если его нет.
  Future<String> loadFullBioImage(int id) async {
    final db = await _db.database;
    return BioImageStore.readFull(db, id);
  }

  /// Сохраняет изображение любого размера. Возвращает значение для
  /// `CharacterModel.bioImageBase64` (миниатюра или небольшая картинка).
  Future<String> setBioImage(int id, Uint8List bytes) async {
    final db = await _db.database;
    return BioImageStore.setImage(db, id, bytes);
  }

  Future<void> clearBioImage(int id) async {
    final db = await _db.database;
    await BioImageStore.clearImage(db, id);
  }
}
