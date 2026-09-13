import '../../models/attack_model.dart';
import '../../models/character_model.dart';
import '../../models/item_model.dart';
import '../../models/spell_model.dart';
import '../models/pdf_import_draft.dart';

/// Maps the remote character sheet's `character` JSON tree (as returned by
/// `POST /i/dnd/character_sheet/store`) into a [PdfImportDraft].
///
/// Field paths below (`main.name`, `stats.base.strength.value`, etc.) are
/// copied verbatim from `data-branch` attributes found on a real captured
/// character-sheet page — not guessed. See character_sheet_remote_importer.dart for the
/// full explanation and the caveat about future sheet-layout changes.
class CharacterSheetMapper {
  const CharacterSheetMapper._();

  static const _abilities = ['strength', 'dexterity', 'constitution', 'intelligence', 'wisdom', 'charisma'];

  static const _abilityShort = {
    'strength': 'str',
    'dexterity': 'dex',
    'constitution': 'con',
    'intelligence': 'int',
    'wisdom': 'wis',
    'charisma': 'cha',
  };

  // Matches the canonical skill keys in data/constants/dnd_data.dart — these
  // already line up 1:1 with the source sheet's data-branch skill keys.
  static const _skills = {
    'acrobatics': 'dexterity',
    'investigation': 'intelligence',
    'athletics': 'strength',
    'perception': 'wisdom',
    'survival': 'wisdom',
    'performance': 'charisma',
    'intimidation': 'charisma',
    'history': 'intelligence',
    'sleight_of_hand': 'dexterity',
    'arcana': 'intelligence',
    'medicine': 'wisdom',
    'deception': 'charisma',
    'nature': 'intelligence',
    'insight': 'wisdom',
    'religion': 'intelligence',
    'stealth': 'dexterity',
    'persuasion': 'charisma',
    'animal_handling': 'wisdom',
  };

  static PdfImportDraft map(Map<String, dynamic> character) {
    final evidence = <PdfImportField>[];
    final warnings = <String>[];

    String str(String path) {
      final value = _get(character, path);
      if (value == null) return '';
      final text = value.toString().trim();
      if (text.isNotEmpty) {
        evidence.add(PdfImportField(key: path, value: text, confidence: 0.95, source: 'external', page: 0));
      }
      return text;
    }

    int intVal(String path, {int fallback = 0}) {
      final value = _get(character, path);
      if (value == null) return fallback;
      if (value is num) return value.toInt();
      final match = RegExp(r'[-+]?\d+').firstMatch(value.toString());
      return match == null ? fallback : int.tryParse(match.group(0)!) ?? fallback;
    }

    final name = str('main.name');
    if (name.isEmpty) {
      throw const CharacterSheetMappingException('В данных персонажа не найдено имя.');
    }

    final classLevelRaw = str('main.class_level');
    final parsedClass = _parseClassLevel(classLevelRaw);

    final savingThrows = <String>{};
    final skillProficiencies = <String>{};
    for (final ability in _abilities) {
      final short = _abilityShort[ability]!;
      if (_get(character, 'stats.base.$ability.savethrow.state') == 'checked') {
        savingThrows.add(short);
      }
    }
    _skills.forEach((skillKey, ability) {
      final state = _get(character, 'stats.base.$ability.skills.$skillKey.state');
      if (state == 'checked' || state == 'x2') {
        skillProficiencies.add(skillKey);
      }
    });

    var deathSaveSuccesses = 0;
    var deathSaveFailures = 0;
    for (var i = 0; i < 3; i++) {
      if (_get(character, 'stats.death_saves.successes.$i') == 'checked') deathSaveSuccesses++;
      if (_get(character, 'stats.death_saves.failures.$i') == 'checked') deathSaveFailures++;
    }

    final hitDiceTotal = str('stats.hit_dice_total');
    final hitDiceType = str('stats.hit_dice');
    final hitDice = _combineHitDice(hitDiceTotal, hitDiceType);

    final spellcastingAbilityRaw = str('spellcasting.ability');

    final character0 = CharacterModel(
      name: name,
      race: str('main.race'),
      className: parsedClass.$1,
      level: parsedClass.$2,
      background: str('main.background'),
      alignment: str('main.alignment'),
      playerName: str('main.player_name'),
      strength: intVal('stats.base.strength.value', fallback: 10),
      dexterity: intVal('stats.base.dexterity.value', fallback: 10),
      constitution: intVal('stats.base.constitution.value', fallback: 10),
      intelligence: intVal('stats.base.intelligence.value', fallback: 10),
      wisdom: intVal('stats.base.wisdom.value', fallback: 10),
      charisma: intVal('stats.base.charisma.value', fallback: 10),
      hp: intVal('stats.hp_current', fallback: 10),
      maxHp: intVal('stats.hp_max', fallback: 10),
      temporaryHp: intVal('stats.hp_temporary', fallback: 0),
      armorClass: intVal('stats.ac', fallback: 10),
      initiative: intVal('stats.initiative', fallback: 0),
      speed: intVal('stats.speed', fallback: 30),
      proficiencyBonus: intVal('stats.proficiency_bonus', fallback: 2),
      inspiration: _get(character, 'stats.inspiration') == 'inspiration',
      hitDice: hitDice,
      deathSaveSuccesses: deathSaveSuccesses,
      deathSaveFailures: deathSaveFailures,
      savingThrowProficiencies: savingThrows,
      skillProficiencies: skillProficiencies,
      xp: intVal('stats.xp', fallback: 0),
      copper: intVal('money.cp', fallback: 0),
      silver: intVal('money.sp', fallback: 0),
      electrum: intVal('money.ep', fallback: 0),
      gold: intVal('money.gp', fallback: 0),
      platinum: intVal('money.pp', fallback: 0),
      spellcastingClass: str('spellcasting.class'),
      spellcastingAbility: _abilityShort[spellcastingAbilityRaw] ?? '',
      personalityTraits: str('personality.traits'),
      ideals: str('personality.ideals'),
      bonds: str('personality.bonds'),
      flaws: str('personality.flaws'),
      proficienciesLanguages: str('other_proficiencies_and_languages'),
      age: str('appearance.age'),
      height: str('appearance.height'),
      weight: str('appearance.weight'),
      eyes: str('appearance.eyes'),
      skin: str('appearance.skin'),
      hair: str('appearance.hair'),
      backstory: str('character_backstory'),
      alliesOrganizations: [str('allies_and_organisations.name'), str('allies_and_organisations.text')]
          .where((s) => s.isNotEmpty)
          .join('\n\n'),
      treasure: str('treasure'),
    );

    final equipmentText = str('equipment');
    final items = equipmentText.isEmpty
        ? const <ItemModel>[]
        : [ItemModel(characterId: 0, name: 'Снаряжение', description: equipmentText)];
    if (equipmentText.isNotEmpty) {
      warnings.add('Снаряжение импортировано как один текстовый предмет; автоматическое разбиение на отдельные предметы будет следующим этапом (см. docs/PDF Importer.md).');
    }

    final featuresText = [str('features_and_traits'), str('additional_features_and_traits')]
        .where((s) => s.isNotEmpty)
        .join('\n\n');
    if (featuresText.isNotEmpty) {
      warnings.add('Особенности импортированы как исходный текст персонажа; автоматическое разбиение на отдельные способности будет следующим этапом.');
    }

    final attacksText = str('attacks_and_spellcasting.text');
    if (attacksText.isNotEmpty) {
      warnings.add('В блоке "Атаки и заклинания" есть дополнительный текст (за пределами таблицы атак), который не был импортирован — добавьте его вручную при необходимости.');
    }

    final attacks = _extractAttacks(character);
    final spells = _extractSpells(character);

    return PdfImportDraft(
      character: character0,
      attacks: attacks,
      spells: spells,
      items: items,
      fields: evidence,
      warnings: warnings,
    );
  }

  static List<AttackModel> _extractAttacks(Map<String, dynamic> character) {
    final raw = _asIndexedList(_get(character, 'attacks_and_spellcasting.fields'));
    final attacks = <AttackModel>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) continue;
      final name = (entry['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
      attacks.add(AttackModel(
        characterId: 0,
        name: name,
        attackBonus: (entry['bonus'] ?? '').toString(),
        damage: (entry['damage_type'] ?? '').toString(),
        sortOrder: i,
      ));
    }
    return attacks;
  }

  static List<SpellModel> _extractSpells(Map<String, dynamic> character) {
    final spellsNode = _get(character, 'spells');
    final levels = _asIndexedList(spellsNode);
    final spells = <SpellModel>[];

    for (var level = 0; level < levels.length; level++) {
      final levelNode = levels[level];
      if (levelNode is! Map) continue;
      final list = _asIndexedList(levelNode['list']);
      for (final entry in list) {
        if (entry is! Map) continue;
        final name = (entry['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final prepared = entry['prepared'];
        spells.add(SpellModel(
          characterId: 0,
          name: name,
          level: level,
          // Level 0 (cantrips) has no prepared checkbox on the sheet —
          // cantrips are always effectively "known"/usable.
          prepared: level == 0 ? true : (prepared == 'checked' || prepared == true),
        ));
      }
    }
    return spells;
  }

  /// Reads a dot-path (e.g. `stats.base.strength.value`) out of a nested
  /// tree of Maps/Lists, exactly mirroring a `data-branch` attribute.
  static dynamic _get(Map<String, dynamic> root, String path) {
    dynamic current = root;
    for (final part in path.split('.')) {
      if (current == null) return null;
      if (current is Map) {
        current = current[part];
      } else if (current is List) {
        final index = int.tryParse(part);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }

  /// The remote sheet serialises some indexed collections as JSON arrays and others
  /// (when sparse) as objects with numeric string keys — this normalizes
  /// either shape into an ordered List.
  static List<dynamic> _asIndexedList(dynamic node) {
    if (node is List) return node;
    if (node is Map) {
      final entries = node.entries.toList()
        ..sort((a, b) {
          final ai = int.tryParse(a.key.toString()) ?? 0;
          final bi = int.tryParse(b.key.toString()) ?? 0;
          return ai.compareTo(bi);
        });
      return entries.map((e) => e.value).toList();
    }
    return const [];
  }

  static (String, int) _parseClassLevel(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return ('', 1);
    final match = RegExp(r'^(.*?)(?:\s+)(\d+)$').firstMatch(cleaned);
    if (match == null) return (cleaned, 1);
    return (match.group(1)!.trim(), int.tryParse(match.group(2)!) ?? 1);
  }

  /// Combines the separate "hit dice total" and "hit dice type" fields into
  /// the single free-text format used elsewhere in the app (e.g. "5к8").
  static String _combineHitDice(String total, String diceType) {
    if (total.isEmpty && diceType.isEmpty) return '';
    if (diceType.isEmpty) return total;
    final hasPrefix = diceType.toLowerCase().contains('к') || diceType.toLowerCase().contains('d');
    return '$total${hasPrefix ? diceType : 'к$diceType'}';
  }
}

class CharacterSheetMappingException implements Exception {
  final String message;
  const CharacterSheetMappingException(this.message);

  @override
  String toString() => message;
}
