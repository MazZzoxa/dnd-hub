import '../../models/attack_model.dart';
import '../../models/character_model.dart';
import '../../models/item_model.dart';
import '../../models/spell_model.dart';
import '../models/pdf_import_draft.dart';

/// Best-effort extractor that turns an arbitrary decoded JSON payload into a
/// [PdfImportDraft] (the draft type is shared between the PDF and URL
/// importers — see docs/PDF Importer.md, next step 6).
///
/// This is intentionally alias-based, the same way the AcroForm PDF importer
/// matches field names/mappingNames: a page or API response found on the
/// internet will not follow any single schema, so instead of hard-coding one
/// site's field layout we look for a set of recognisable keys (English and
/// Russian).
///
/// This is the *fallback* path for sites without a dedicated importer.
/// The primary supported remote sheet format has its
/// own dedicated [CharacterSheetRemoteImporter] (see the dedicated remote-sheet importer),
/// built from a real captured sheet response rather than guesswork, so
/// Supported remote sheet URLs never reach this class. This extractor only runs for other/
/// unknown sites, where alias-guessing at flat JSON keys is the best that
/// can be done without a captured sample. If it fails to detect a character,
/// or detects one with missing/wrong fields, capture the JSON the site
/// actually returns (browser dev tools → Network tab) and extend the alias
/// lists accordingly — this extractor returns null rather than guessing
/// further when it isn't confident it has found a character, the same
/// intentional-failure philosophy the PDF importer uses.
class GenericCharacterExtractor {
  const GenericCharacterExtractor._();

  /// Searches [root] (already-decoded JSON: Map/List/primitives) for a
  /// character-shaped object and builds a draft from it. Returns null if
  /// nothing sufficiently character-like was found, so callers can fail
  /// explicitly instead of importing garbage.
  static PdfImportDraft? tryExtract(dynamic root, {required String sourceUrl}) {
    final candidate = _findCharacterLikeMap(root, 0);
    if (candidate == null) return null;

    final normalized = _normalizeMap(candidate);
    final evidence = <PdfImportField>[];
    final warnings = <String>[
      'Импорт по ссылке — экспериментальная функция: сопоставление полей выполняется '
          'эвристически. Проверьте данные персонажа перед сохранением.',
    ];

    String str(List<String> aliases, {String? evidenceKey}) {
      for (final alias in aliases) {
        final value = normalized[_normalizeKey(alias)];
        if (value == null) continue;
        final text = value.toString().trim();
        if (text.isEmpty) continue;
        evidence.add(PdfImportField(
          key: evidenceKey ?? alias,
          value: text,
          confidence: 0.6,
          source: 'url',
          page: 0,
        ));
        return text;
      }
      return '';
    }

    int intVal(List<String> aliases, {required int fallback, String? evidenceKey}) {
      final raw = str(aliases, evidenceKey: evidenceKey);
      if (raw.isEmpty) return fallback;
      final match = RegExp(r'[-+]?\d+').firstMatch(raw);
      if (match == null) return fallback;
      return int.tryParse(match.group(0)!) ?? fallback;
    }

    bool boolVal(List<String> aliases) {
      for (final alias in aliases) {
        final value = normalized[_normalizeKey(alias)];
        if (value == null) continue;
        if (value is bool) return value;
        final text = value.toString().trim().toLowerCase();
        if (text == 'true' || text == '1' || text == 'да' || text == 'yes') return true;
        if (text == 'false' || text == '0' || text == 'нет' || text == 'no') return false;
      }
      return false;
    }

    final name = str(['name', 'charactername', 'character_name', 'имя', 'имяперсонажа'], evidenceKey: 'name');
    if (name.isEmpty) return null;

    final classRaw = str(['class', 'className', 'класс'], evidenceKey: 'className');
    final level = intVal(['level', 'classlevel', 'уровень'], fallback: 1, evidenceKey: 'level');

    final character = CharacterModel(
      name: name,
      race: str(['race', 'раса'], evidenceKey: 'race'),
      className: classRaw,
      background: str(['background', 'предыстория'], evidenceKey: 'background'),
      level: level,
      alignment: str(['alignment', 'мировоззрение'], evidenceKey: 'alignment'),
      playerName: str(['playername', 'player_name', 'имяигрока'], evidenceKey: 'playerName'),
      strength: intVal(['strength', 'str', 'сила'], fallback: 10),
      dexterity: intVal(['dexterity', 'dex', 'ловкость'], fallback: 10),
      constitution: intVal(['constitution', 'con', 'телосложение'], fallback: 10),
      intelligence: intVal(['intelligence', 'int', 'интеллект'], fallback: 10),
      wisdom: intVal(['wisdom', 'wis', 'мудрость'], fallback: 10),
      charisma: intVal(['charisma', 'cha', 'харизма'], fallback: 10),
      hp: intVal(['hp', 'currenthp', 'hitpoints', 'текущиехиты'], fallback: 10),
      maxHp: intVal(['maxhp', 'hpmax', 'maxhitpoints', 'максимумхитов'], fallback: 10),
      temporaryHp: intVal(['temphp', 'temporaryhp', 'временныехиты'], fallback: 0),
      armorClass: intVal(['armorclass', 'ac', 'кд'], fallback: 10),
      initiative: intVal(['initiative', 'инициатива'], fallback: 0),
      speed: intVal(['speed', 'скорость'], fallback: 30),
      proficiencyBonus: intVal(['proficiencybonus', 'бонусмастерства'], fallback: 2),
      inspiration: boolVal(['inspiration', 'вдохновение']),
      hitDice: str(['hitdice', 'hd', 'костихитов'], evidenceKey: 'hitDice'),
      xp: intVal(['xp', 'experience', 'опыт'], fallback: 0),
      copper: intVal(['cp', 'copper', 'мм'], fallback: 0),
      silver: intVal(['sp', 'silver', 'см'], fallback: 0),
      electrum: intVal(['ep', 'electrum', 'эм'], fallback: 0),
      gold: intVal(['gp', 'gold', 'зм'], fallback: 0),
      platinum: intVal(['pp', 'platinum', 'пм'], fallback: 0),
      spellcastingClass: classRaw,
      personalityTraits: str(['personalitytraits', 'чертыхарактера'], evidenceKey: 'personalityTraits'),
      ideals: str(['ideals', 'идеалы'], evidenceKey: 'ideals'),
      bonds: str(['bonds', 'привязанности'], evidenceKey: 'bonds'),
      flaws: str(['flaws', 'слабости'], evidenceKey: 'flaws'),
      proficienciesLanguages: str(['proficiencieslanguages', 'владенияязыки'], evidenceKey: 'proficienciesLanguages'),
      age: str(['age', 'возраст'], evidenceKey: 'age'),
      height: str(['height', 'рост'], evidenceKey: 'height'),
      weight: str(['weight', 'вес'], evidenceKey: 'weight'),
      eyes: str(['eyes', 'глаза'], evidenceKey: 'eyes'),
      skin: str(['skin', 'кожа'], evidenceKey: 'skin'),
      hair: str(['hair', 'волосы'], evidenceKey: 'hair'),
      backstory: str(['backstory', 'предысторияперсонажа'], evidenceKey: 'backstory'),
      alliesOrganizations: str(['alliesorganizations', 'союзникииорганизации'], evidenceKey: 'alliesOrganizations'),
      treasure: str(['treasure', 'сокровища'], evidenceKey: 'treasure'),
    );

    final spells = _extractSpells(normalized, warnings);
    final items = _extractItems(normalized, warnings);
    final attacks = _extractAttacks(normalized);

    return PdfImportDraft(
      character: character,
      attacks: attacks,
      spells: spells,
      items: items,
      fields: evidence,
      warnings: warnings,
    );
  }

  static List<SpellModel> _extractSpells(Map<String, dynamic> normalized, List<String> warnings) {
    final raw = _listValue(normalized, ['spells', 'заклинания']);
    if (raw == null) return const [];

    final spells = <SpellModel>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = _normalizeMap(entry);
      final name = map[_normalizeKey('name')]?.toString().trim() ??
          map[_normalizeKey('название')]?.toString().trim();
      if (name == null || name.isEmpty) continue;
      spells.add(SpellModel(
        characterId: 0,
        name: name,
        level: _asInt(map[_normalizeKey('level')] ?? map[_normalizeKey('уровень')]) ?? 0,
        description: (map[_normalizeKey('description')] ?? map[_normalizeKey('описание')])?.toString() ?? '',
        prepared: map[_normalizeKey('prepared')] == true || map[_normalizeKey('подготовлено')] == true,
      ));
    }
    if (spells.isEmpty && raw.isNotEmpty) {
      warnings.add('Найден список заклинаний, но не удалось распознать ни одной записи.');
    }
    return spells;
  }

  static List<ItemModel> _extractItems(Map<String, dynamic> normalized, List<String> warnings) {
    final raw = _listValue(normalized, ['items', 'inventory', 'equipmentlist', 'снаряжение', 'инвентарь']);
    if (raw != null) {
      final items = <ItemModel>[];
      for (final entry in raw) {
        if (entry is Map) {
          final map = _normalizeMap(entry);
          final name = (map[_normalizeKey('name')] ?? map[_normalizeKey('название')])?.toString().trim();
          if (name == null || name.isEmpty) continue;
          items.add(ItemModel(
            characterId: 0,
            name: name,
            quantity: _asInt(map[_normalizeKey('quantity')] ?? map[_normalizeKey('количество')]) ?? 1,
            description: (map[_normalizeKey('description')] ?? map[_normalizeKey('описание')])?.toString() ?? '',
          ));
        } else if (entry is String && entry.trim().isNotEmpty) {
          items.add(ItemModel(characterId: 0, name: entry.trim()));
        }
      }
      return items;
    }

    // Some sheets store equipment as one free-text block rather than a list.
    final text = normalized[_normalizeKey('equipment')]?.toString().trim() ??
        normalized[_normalizeKey('снаряжение')]?.toString().trim();
    if (text != null && text.isNotEmpty) {
      warnings.add('Снаряжение импортировано как один текстовый предмет; проверьте и разделите его вручную при необходимости.');
      return [ItemModel(characterId: 0, name: 'Снаряжение', description: text)];
    }
    return const [];
  }

  static List<AttackModel> _extractAttacks(Map<String, dynamic> normalized) {
    final raw = _listValue(normalized, ['attacks', 'атаки']);
    if (raw == null) return const [];
    final attacks = <AttackModel>[];
    var order = 0;
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = _normalizeMap(entry);
      final name = (map[_normalizeKey('name')] ?? map[_normalizeKey('название')])?.toString().trim();
      if (name == null || name.isEmpty) continue;
      attacks.add(AttackModel(
        characterId: 0,
        name: name,
        attackBonus: (map[_normalizeKey('attackbonus')] ?? map[_normalizeKey('бонусатаки')])?.toString() ?? '',
        damage: (map[_normalizeKey('damage')] ?? map[_normalizeKey('урон')])?.toString() ?? '',
        sortOrder: order++,
      ));
    }
    return attacks;
  }

  static List<dynamic>? _listValue(Map<String, dynamic> normalized, List<String> aliases) {
    for (final alias in aliases) {
      final value = normalized[_normalizeKey(alias)];
      if (value is List) return value;
    }
    return null;
  }

  /// Depth-first search for a Map that looks like a character record.
  /// Stops at a shallow depth to avoid pathological payloads (e.g. giant
  /// nested site-wide state blobs) taking a long time to scan.
  static Map<String, dynamic>? _findCharacterLikeMap(dynamic node, int depth) {
    if (depth > 8) return null;

    if (node is Map) {
      final map = _normalizeMap(node);
      if (_looksLikeCharacter(map)) return Map<String, dynamic>.from(node);
      for (final value in node.values) {
        final found = _findCharacterLikeMap(value, depth + 1);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final item in node) {
        final found = _findCharacterLikeMap(item, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  static const _nameKeys = {'name', 'charactername', 'character_name', 'имя', 'имяперсонажа'};

  static const _signalKeys = {
    'race', 'раса',
    'class', 'className', 'класс',
    'level', 'уровень',
    'strength', 'str', 'сила',
    'dexterity', 'dex', 'ловкость',
    'armorclass', 'ac', 'кд',
    'hp', 'hitpoints', 'текущиехиты',
    'background', 'предыстория',
  };

  static bool _looksLikeCharacter(Map<String, dynamic> normalized) {
    final hasName = _nameKeys.any((k) => normalized.containsKey(_normalizeKey(k)) &&
        (normalized[_normalizeKey(k)]?.toString().trim().isNotEmpty ?? false));
    if (!hasName) return false;

    final signalCount = _signalKeys
        .map(_normalizeKey)
        .where(normalized.containsKey)
        .length;
    return signalCount >= 2;
  }

  static Map<String, dynamic> _normalizeMap(Map raw) {
    final result = <String, dynamic>{};
    raw.forEach((key, value) {
      result[_normalizeKey(key.toString())] = value;
    });
    return result;
  }

  /// Normalizes a key for loose matching: lower-cased, Ё→Е, and stripped of
  /// anything that isn't a letter or digit (so `Character Name`,
  /// `character_name` and `characterName` all collapse to the same key).
  static String _normalizeKey(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^a-zа-я0-9]'), '');
  }

  static int? _asInt(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }
}
