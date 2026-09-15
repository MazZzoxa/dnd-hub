import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_hub/data/database/database_helper.dart';
import 'package:dnd_hub/data/export/export_manager.dart';
import 'package:dnd_hub/data/import/import_manager.dart';
import 'package:dnd_hub/data/models/character_model.dart';

void main() {
  test('character export/import preserves XP history', () async {
    final db = await DatabaseHelper.instance.database;

    final source = CharacterModel(name: 'XP Test', xp: 900, level: 3);
    final sourceId = await db.insert('characters', source.toMap()..remove('id'));
    await db.insert('xp_transactions', {
      'character_id': sourceId,
      'delta': 900,
      'xp_before': 0,
      'xp_after': 900,
      'level_before': 1,
      'level_after': 3,
      'reason': 'Quest reward',
      'created_at': DateTime.utc(2026, 9, 15).toIso8601String(),
    });

    final exportedPayload = {
      'schema': ExportManager.schema,
      'formatVersion': ExportManager.formatVersion,
      'exportType': 'character',
      'character': source.toMap(),
      'inventory': const [],
      'spells': const [],
      'abilities': const [],
      'attacks': const [],
      'spellSlots': const [],
      'notes': const [],
      'xpHistory': [
        {
          'delta': 900,
          'xp_before': 0,
          'xp_after': 900,
          'level_before': 1,
          'level_after': 3,
          'reason': 'Quest reward',
          'created_at': '2026-09-15T00:00:00.000Z',
        },
      ],
      'libraryItems': const [],
    };

    final result = await ImportManager().importBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(exportedPayload))),
    );

    final importedId = result.importedCharacterId!;
    final rows = await db.query(
      'xp_transactions',
      where: 'character_id = ?',
      whereArgs: [importedId],
    );

    expect(rows, hasLength(1));
    expect(rows.single['delta'], 900);
    expect(rows.single['reason'], 'Quest reward');
    expect(rows.single['character_id'], importedId);
    expect(rows.single['id'], isNot(sourceId));

    await db.delete('characters', where: 'id = ?', whereArgs: [importedId]);
    await db.delete('characters', where: 'id = ?', whereArgs: [sourceId]);
    await DatabaseHelper.instance.close();
  });
}
