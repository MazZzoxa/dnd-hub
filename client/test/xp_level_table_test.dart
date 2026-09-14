import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_hub/domain/xp/xp_level_table.dart';
import 'package:dnd_hub/domain/xp/xp_service.dart';
import 'package:dnd_hub/data/models/character_model.dart';

void main() {
  test('XP thresholds calculate D&D 5e levels', () {
    expect(XpLevelTable.levelForXp(0), 1);
    expect(XpLevelTable.levelForXp(299), 1);
    expect(XpLevelTable.levelForXp(300), 2);
    expect(XpLevelTable.levelForXp(899), 2);
    expect(XpLevelTable.levelForXp(900), 3);
    expect(XpLevelTable.levelForXp(355000), 20);
    expect(XpLevelTable.levelForXp(999999), 20);
  });

  test('progress exposes current and next level thresholds', () {
    final character = CharacterModel(name: 'Kael', xp: 600);
    final progress = XpService().progress(character);
    expect(progress.level, 2);
    expect(progress.currentLevelXp, 300);
    expect(progress.nextLevelXp, 900);
    expect(progress.progress, closeTo(0.5, 0.0001));
  });

  test('level 20 is a completed progression bar', () {
    final character = CharacterModel(name: 'Kael', xp: 355000, level: 20);
    final progress = XpService().progress(character);
    expect(progress.level, 20);
    expect(progress.nextLevelXp, isNull);
    expect(progress.progress, 1.0);
  });
}
