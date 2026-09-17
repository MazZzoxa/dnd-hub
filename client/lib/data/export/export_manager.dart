import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

import '../database/database_helper.dart';
import '../models/character_model.dart';
import '../models/item_model.dart';
import '../models/spell_model.dart';
import '../models/ability_model.dart';
import '../models/library_item_model.dart';

/// Создаёт переносимые JSON-структуры D&D Hub.
///
/// Формат `.dndhub` намеренно является обычным JSON с другим расширением.
/// Благодаря этому файл остаётся читаемым человеком, легко валидируется и
/// в будущем может быть использован тем же ImportManager.
class ExportManager {
  static const int formatVersion = 2;
  static const String schema = 'dnd-hub';

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<String?> exportCharacter(
    CharacterModel character, {
    required ExportFileFormat format,
  }) async {
    final id = character.id;
    if (id == null) throw StateError('Нельзя экспортировать персонажа без id.');

    final db = await _db.database;
    final itemRows = await db.query('items', where: 'character_id = ?', whereArgs: [id], orderBy: 'category, name COLLATE NOCASE');
    final spellRows = await db.query('spells', where: 'character_id = ?', whereArgs: [id], orderBy: 'level, name COLLATE NOCASE');
    final abilityRows = await db.query('abilities', where: 'character_id = ?', whereArgs: [id], orderBy: 'sort_order, name COLLATE NOCASE');
    final attackRows = await db.query('attacks', where: 'character_id = ?', whereArgs: [id], orderBy: 'sort_order, id');
    final slotRows = await db.query('spell_slots', where: 'character_id = ?', whereArgs: [id], orderBy: 'level');
    final noteRows = await db.query('notes', where: 'character_id = ?', whereArgs: [id], orderBy: 'created_at DESC');

    final items = itemRows.map(ItemModel.fromMap).toList();
    final spells = spellRows.map(SpellModel.fromMap).toList();
    final abilities = abilityRows.map(AbilityModel.fromMap).toList();

    final referencedLibraryIds = <int>{
      for (final item in items)
        if (item.libraryItemId != null) item.libraryItemId!,
      for (final spell in spells)
        if (spell.libraryItemId != null) spell.libraryItemId!,
      for (final ability in abilities)
        if (ability.libraryItemId != null) ability.libraryItemId!,
    };

    final libraryItems = <LibraryItemModel>[];
    for (final libraryId in referencedLibraryIds) {
      final rows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [libraryId],
        limit: 1,
      );
      if (rows.isNotEmpty) libraryItems.add(LibraryItemModel.fromMap(rows.first));
    }

    final payload = <String, dynamic>{
      'schema': schema,
      'formatVersion': formatVersion,
      'exportType': 'character',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'character': _characterMap(character),
      'inventory': itemRows.map(_cleanDbMap).toList(),
      'spells': spellRows.map(_cleanDbMap).toList(),
      'abilities': abilityRows.map(_cleanDbMap).toList(),
      'attacks': attackRows.map(_cleanDbMap).toList(),
      'spellSlots': slotRows.map(_cleanDbMap).toList(),
      'notes': noteRows.map(_cleanDbMap).toList(),
      'xpHistory': (await db.query('xp_transactions', where: 'character_id = ?', whereArgs: [id], orderBy: 'created_at DESC, id DESC')).map(_cleanDbMap).toList(),
      'libraryItems': libraryItems.map(_libraryMap).toList(),
    };

    final json = _prettyJson(payload);
    return _save(json, _characterFileName(character.name), format);
  }

  Future<String?> exportLibraryItem(
    LibraryItemModel item, {
    required ExportFileFormat format,
  }) async {
    final payload = <String, dynamic>{
      'schema': schema,
      'formatVersion': formatVersion,
      'exportType': 'libraryItem',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'item': _libraryMap(item),
    };
    return _save(
      _prettyJson(payload),
      _libraryItemFileName(item.name),
      format,
    );
  }

  /// Создаёт полную резервную копию текущего локального состояния D&D Hub.
  ///
  /// Backup — это не экспорт одного игрового объекта: в файл попадают все
  /// существующие на текущем этапе приложения таблицы SQLite с исходными ID,
  /// поэтому внешние связи между персонажами, их данными и Local Library
  /// сохраняются без преобразований.
  Future<String?> exportBackup() async {
    final db = await _db.database;

    final tables = <String, List<Map<String, dynamic>>>{
      'characters': await db.query('characters', orderBy: 'id'),
      'libraryItems': await db.query('library_items', orderBy: 'id'),
      'items': await db.query('items', orderBy: 'id'),
      'spells': await db.query('spells', orderBy: 'id'),
      'abilities': await db.query('abilities', orderBy: 'id'),
      'notes': await db.query('notes', orderBy: 'id'),
      'attacks': await db.query('attacks', orderBy: 'id'),
      'spellSlots': await db.query('spell_slots', orderBy: 'character_id, level'),
      'campaigns': await db.query('campaigns', orderBy: 'id'),
      'campaignMembers': await db.query('campaign_members', orderBy: 'id'),
      'campaignSessions': await db.query('campaign_sessions', orderBy: 'id'),
      'xpTransactions': await db.query('xp_transactions', orderBy: 'character_id, created_at, id'),
    };

    final payload = <String, dynamic>{
      'schema': schema,
      'formatVersion': formatVersion,
      'exportType': 'backup',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'databaseVersion': 8,
      'sections': [
        'characters',
        'libraryItems',
        'items',
        'spells',
        'abilities',
        'notes',
        'attacks',
        'spellSlots',
        'campaigns',
        'campaignMembers',
        'campaignSessions',
        'xpTransactions',
      ],
      'data': tables,
    };

    return _save(_prettyJson(payload), 'dndhub_backup', ExportFileFormat.dndhub);
  }

  Future<String?> exportLibrary({
    required ExportFileFormat format,
  }) async {
    final db = await _db.database;
    final rows = await db.query('library_items', orderBy: 'type, name COLLATE NOCASE');
    final items = rows.map(LibraryItemModel.fromMap).toList();

    final payload = <String, dynamic>{
      'schema': schema,
      'formatVersion': formatVersion,
      'exportType': 'library',
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'libraryItems': items.map(_libraryMap).toList(),
    };

    return _save(_prettyJson(payload), 'dnd_hub_library', format);
  }

  Map<String, dynamic> _characterMap(CharacterModel character) {
    final map = character.toMap();
    map.remove('character_id');
    return map;
  }

  Map<String, dynamic> _libraryMap(LibraryItemModel item) {
    return {
      if (item.id != null) 'id': item.id,
      'type': item.type.name,
      'name': item.name,
      'data': item.data,
      'sourceType': item.sourceType.name,
      'sourceUrl': item.sourceUrl,
      'createdAt': item.createdAt.toIso8601String(),
      'updatedAt': item.updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _cleanDbMap(Map<String, dynamic> row) {
    final result = Map<String, dynamic>.from(row);
    result.remove('character_id');
    return result;
  }

  String _prettyJson(Map<String, dynamic> payload) {
    const encoder = JsonEncoder.withIndent('  ');
    return '${encoder.convert(payload)}\n';
  }

  Future<String?> _save(
    String content,
    String baseName,
    ExportFileFormat format,
  ) async {
    final extension = format == ExportFileFormat.json ? 'json' : 'dndhub';
    final bytes = Uint8List.fromList(utf8.encode(content));
    final mimeType = format == ExportFileFormat.json
        ? MimeType.json
        : MimeType.custom;

    // На Android/iOS/macOS/Windows используем системный диалог
    // выбора места сохранения. На Linux остаётся штатное сохранение
    // в каталог загрузок, поддерживаемое file_saver.
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows) {
      final savedPath = await FileSaver.instance.saveAs(
        name: baseName,
        bytes: bytes,
        fileExtension: extension,
        mimeType: mimeType,
        customMimeType: format == ExportFileFormat.dndhub
            ? 'application/vnd.dndhub+json'
            : null,
      );
      return savedPath;
    }

    final savedPath = await FileSaver.instance.saveFile(
      name: baseName,
      bytes: bytes,
      fileExtension: extension,
      mimeType: mimeType,
      customMimeType: format == ExportFileFormat.dndhub
          ? 'application/vnd.dndhub+json'
          : null,
    );
    return savedPath;
  }

  String _sanitizeName(String value) {
    final trimmed = value.trim().isEmpty ? 'dnd_hub_export' : value.trim();
    final sanitized = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    return sanitized.replaceAll(RegExp(r'\s+'), '_');
  }

  String _characterFileName(String name) {
    return 'character_${_sanitizeName(name)}';
  }

  String _libraryItemFileName(String name) {
    return 'library_${_sanitizeName(name)}';
  }
}

enum ExportFileFormat {
  json,
  dndhub,
}
