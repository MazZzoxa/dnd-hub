import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

/// Хранилище изображений био персонажей без ограничения по размеру.
///
/// Проблема, которую оно решает: на Android sqflite читает результат запроса
/// через CursorWindow (~2 МБ на окно). Строка `characters`, в которой лежит
/// картинка на несколько мегабайт, не помещается в окно, запрос падает и
/// список персонажей не загружается.
///
/// Схема хранения:
/// * `character_images.data` — полное изображение (base64), любой размер.
///   Читается ТОЛЬКО кусками через `substr`, поэтому лимит окна не мешает.
/// * `characters.bio_image` — маленькая миниатюра (или сама картинка, если она
///   небольшая). Именно её видят все обычные запросы, аватары и синхронизация.
///
/// В экспорт (`.json` / `.dndhub` / backup) всегда попадает полное изображение.
/// При импорте большая картинка сначала попадает в `characters.bio_image`
/// целиком (INSERT не ограничен окном), а затем [migrateOversized] переносит её
/// в `character_images` и заменяет миниатюрой.
class BioImageStore {
  BioImageStore._();

  /// Картинки (base64-символов) не больше этого значения остаются прямо в
  /// `characters.bio_image` без отдельного хранения.
  static const int inlineLimit = 150000;

  /// Сторона миниатюры в пикселях.
  static const int thumbSide = 256;

  /// Размер одного куска при чтении (символов). Заведомо меньше окна курсора.
  static const int _chunkSize = 300000;

  /// Значения bio_image крупнее этого никогда не попадают в обычный SELECT.
  static const int _safeReadLimit = 1000000;

  static const String _createTableSql = '''
    CREATE TABLE IF NOT EXISTS character_images (
      character_id INTEGER PRIMARY KEY,
      data TEXT NOT NULL,
      FOREIGN KEY (character_id) REFERENCES characters(id) ON DELETE CASCADE
    )
  ''';

  static Future<void> ensureSchema(DatabaseExecutor db) {
    return db.execute(_createTableSql);
  }

  /// Список колонок для `SELECT ... FROM characters`, который никогда не
  /// вытаскивает гигантский bio_image (вместо него отдаётся пустая строка).
  /// Это страховка: даже если в базе осталась «тяжёлая» строка, список
  /// персонажей всё равно загрузится.
  static Future<String> safeSelectList(DatabaseExecutor db) async {
    final info = await db.rawQuery('PRAGMA table_info(characters)');
    final parts = <String>[
      for (final row in info)
        if (row['name'] != 'bio_image') '"${row['name']}"',
    ];
    parts.add(
      "CASE WHEN length(bio_image) <= $_safeReadLimit THEN bio_image ELSE '' END AS bio_image",
    );
    return parts.join(', ');
  }

  static Future<String> _readChunked(
    DatabaseExecutor db, {
    required String table,
    required String column,
    required String keyColumn,
    required int id,
  }) async {
    final lengthRows = await db.rawQuery(
      'SELECT length($column) AS n FROM $table WHERE $keyColumn = ?',
      [id],
    );
    if (lengthRows.isEmpty) return '';
    final total = (lengthRows.first['n'] as num?)?.toInt() ?? 0;
    if (total <= 0) return '';

    final buffer = StringBuffer();
    for (var start = 1; start <= total; start += _chunkSize) {
      final rows = await db.rawQuery(
        'SELECT substr($column, ?, ?) AS part FROM $table WHERE $keyColumn = ?',
        [start, _chunkSize, id],
      );
      if (rows.isEmpty) break;
      buffer.write(rows.first['part'] ?? '');
    }
    return buffer.toString();
  }

  /// Полное изображение персонажа в base64 (пустая строка, если его нет).
  static Future<String> readFull(DatabaseExecutor db, int characterId) async {
    await ensureSchema(db);
    final stored = await _readChunked(
      db,
      table: 'character_images',
      column: 'data',
      keyColumn: 'character_id',
      id: characterId,
    );
    if (stored.isNotEmpty) return stored;
    return _readChunked(
      db,
      table: 'characters',
      column: 'bio_image',
      keyColumn: 'id',
      id: characterId,
    );
  }

  /// Миниатюра (PNG, base64). Пустая строка, если декодировать не удалось.
  static Future<String> makeThumbnail(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes, targetWidth: thumbSide);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return '';
      return base64Encode(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (error) {
      debugPrint('BioImageStore: не удалось создать миниатюру: $error');
      return '';
    } finally {
      codec?.dispose();
    }
  }

  /// Сохраняет новое изображение без ограничения размера.
  /// Возвращает значение для `CharacterModel.bioImageBase64`
  /// (миниатюра или сама небольшая картинка).
  static Future<String> setImage(
    Database db,
    int characterId,
    Uint8List bytes,
  ) async {
    await ensureSchema(db);
    final full = base64Encode(bytes);

    if (full.length <= inlineLimit) {
      await db.transaction((txn) async {
        await txn.delete(
          'character_images',
          where: 'character_id = ?',
          whereArgs: [characterId],
        );
        await txn.update(
          'characters',
          {'bio_image': full},
          where: 'id = ?',
          whereArgs: [characterId],
        );
      });
      return full;
    }

    final thumb = await makeThumbnail(bytes);
    await db.transaction((txn) async {
      await txn.insert(
        'character_images',
        {'character_id': characterId, 'data': full},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.update(
        'characters',
        {'bio_image': thumb},
        where: 'id = ?',
        whereArgs: [characterId],
      );
    });
    return thumb;
  }

  static Future<void> clearImage(Database db, int characterId) async {
    await ensureSchema(db);
    await db.transaction((txn) async {
      await txn.delete(
        'character_images',
        where: 'character_id = ?',
        whereArgs: [characterId],
      );
      await txn.update(
        'characters',
        {'bio_image': ''},
        where: 'id = ?',
        whereArgs: [characterId],
      );
    });
  }

  static Future<void> deleteImage(DatabaseExecutor db, int characterId) async {
    await ensureSchema(db);
    await db.delete(
      'character_images',
      where: 'character_id = ?',
      whereArgs: [characterId],
    );
  }

  static Future<int>? _running;

  /// Переносит «тяжёлые» изображения из `characters.bio_image` в
  /// `character_images`, оставляя в строке миниатюру. Безопасно вызывать
  /// сколько угодно раз (после импорта, восстановления backup, при загрузке
  /// списка): уже обработанные строки пропускаются.
  static Future<int> migrateOversized(Database db) {
    final running = _running;
    if (running != null) return running;
    final future = _migrate(db).whenComplete(() => _running = null);
    _running = future;
    return future;
  }

  static Future<int> _migrate(Database db) async {
    var migrated = 0;
    try {
      await ensureSchema(db);
      final rows = await db.rawQuery(
        '''
        SELECT c.id AS id,
               length(c.bio_image) AS n,
               EXISTS(SELECT 1 FROM character_images i WHERE i.character_id = c.id) AS has_full
        FROM characters c
        WHERE length(c.bio_image) > ?
        ''',
        [inlineLimit],
      );

      for (final row in rows) {
        final id = (row['id'] as num).toInt();
        final length = (row['n'] as num?)?.toInt() ?? 0;
        final hasFull = ((row['has_full'] as num?) ?? 0) != 0;

        // Полное изображение уже вынесено, а в строке лежит нормальная
        // миниатюра — делать нечего.
        if (hasFull && length <= _safeReadLimit) continue;

        try {
          final source = hasFull
              ? await _readChunked(
                  db,
                  table: 'character_images',
                  column: 'data',
                  keyColumn: 'character_id',
                  id: id,
                )
              : await _readChunked(
                  db,
                  table: 'characters',
                  column: 'bio_image',
                  keyColumn: 'id',
                  id: id,
                );

          var thumb = '';
          try {
            thumb = await makeThumbnail(base64Decode(source));
          } catch (_) {
            thumb = '';
          }

          await db.transaction((txn) async {
            if (!hasFull) {
              await txn.insert(
                'character_images',
                {'character_id': id, 'data': source},
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
            }
            await txn.update(
              'characters',
              {'bio_image': thumb},
              where: 'id = ?',
              whereArgs: [id],
            );
          });
          migrated++;
        } catch (error) {
          debugPrint('BioImageStore: не удалось перенести изображение #$id: $error');
        }
      }
    } catch (error) {
      debugPrint('BioImageStore: миграция изображений не выполнена: $error');
    }
    return migrated;
  }
}
