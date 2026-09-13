import 'dart:convert';

import '../database/database_helper.dart';
import '../models/ability_model.dart';
import '../models/item_model.dart';
import '../models/library_item_model.dart';
import '../models/spell_model.dart';

/// Переносит существующий объект персонажа в глобальную библиотеку.
///
/// Запись персонажа не дублируется: созданный объект становится источником
/// для этой же записи через library_item_id.
class CharacterLibraryService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<LibraryItemModel> addItem(ItemModel item) => _add(
        table: 'items',
        characterRowId: item.id,
        existingLibraryId: item.libraryItemId,
        type: LibraryItemType.item,
        name: item.name,
        data: {
          'category': item.category,
          'weight': item.weight,
          'description': item.description,
        },
        sourceUrl: item.sourceUrl,
      );

  Future<LibraryItemModel> addSpell(SpellModel spell) => _add(
        table: 'spells',
        characterRowId: spell.id,
        existingLibraryId: spell.libraryItemId,
        type: LibraryItemType.spell,
        name: spell.name,
        data: {
          'level': spell.level,
          'school': spell.type,
          'range': spell.range,
          'castingTime': spell.castingTime,
          'duration': spell.duration,
          'components': spell.components,
          'description': spell.description,
        },
        sourceUrl: spell.sourceUrl,
      );

  Future<LibraryItemModel> addAbility(AbilityModel ability) => _add(
        table: 'abilities',
        characterRowId: ability.id,
        existingLibraryId: ability.libraryItemId,
        type: LibraryItemType.ability,
        name: ability.name,
        data: {
          'source': ability.source,
          'description': ability.description,
        },
        sourceUrl: ability.sourceUrl,
      );

  Future<LibraryItemModel> _add({
    required String table,
    required int? characterRowId,
    required int? existingLibraryId,
    required LibraryItemType type,
    required String name,
    required Map<String, dynamic> data,
    String sourceUrl = '',
  }) async {
    if (characterRowId == null) {
      throw StateError('Нельзя добавить в библиотеку объект без id.');
    }

    final db = await _db.database;

    if (existingLibraryId != null) {
      final rows = await db.query(
        'library_items',
        where: 'id = ?',
        whereArgs: [existingLibraryId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return LibraryItemModel.fromMap(rows.first);
      }
    }

    final now = DateTime.now();
    final item = LibraryItemModel(
      type: type,
      name: name.trim(),
      data: data,
      sourceType: LibrarySourceType.userCreated,
      sourceUrl: sourceUrl,
      createdAt: now,
      updatedAt: now,
    );

    final newLibraryId = await db.transaction((txn) async {
      final libraryId = await txn.insert('library_items', item.toMap());
      await txn.update(
        table,
        {'library_item_id': libraryId},
        where: 'id = ?',
        whereArgs: [characterRowId],
      );
      return libraryId;
    });

    return item.copyWith(id: newLibraryId);
  }
}
