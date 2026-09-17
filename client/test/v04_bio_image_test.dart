import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_hub/data/database/database_helper.dart';
import 'package:dnd_hub/data/models/character_model.dart';
import 'package:dnd_hub/data/repositories/character_repository.dart';

void main() {
  test('v0.4.1 schema stores and reads character bio image', () async {
    final db = await DatabaseHelper.instance.database;
    final columns = await db.rawQuery('PRAGMA table_info(characters)');
    expect(columns.any((row) => row['name'] == 'bio_image'), isTrue);

    const image = 'aGVsbG8=';
    final characterId = await CharacterRepository().create(
      const CharacterModel(name: 'Bio image test', bioImageBase64: image),
    );
    final loaded = await CharacterRepository().getById(characterId);

    expect(loaded, isNotNull);
    expect(loaded!.bioImageBase64, image);

    await db.delete('characters', where: 'id = ?', whereArgs: [characterId]);
    await DatabaseHelper.instance.close();
  });
}
