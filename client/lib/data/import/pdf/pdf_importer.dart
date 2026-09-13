import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../models/attack_model.dart';
import '../../models/character_model.dart';
import '../../models/item_model.dart';
import '../../models/spell_model.dart';
import '../models/pdf_import_draft.dart';
import 'pdf_ocr_extractor.dart';

/// Local-first PDF importer based exclusively on AcroForm data.
///
/// Local-first PDF importer. All current extraction comes from AcroForm
/// fields; semantic mapping is driven by field names and mapping names.
class PdfImporter {
  /// Synchronous AcroForm-only parse used by callers that already know the
  /// document contains interactive form data.
  PdfImportDraft parse(Uint8List bytes) {
    if (bytes.length < 4 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
      throw const PdfImportException('Файл не похож на PDF.');
    }

    final document = PdfDocument(inputBytes: bytes);
    try {
      final fields = _extractFormFields(document);
      return _buildDraft(fields);
    } catch (e) {
      if (e is PdfImportException) rethrow;
      throw PdfImportException('Не удалось разобрать AcroForm PDF: $e');
    } finally {
      document.dispose();
    }
  }

  List<_RawPdfField> _extractFormFields(PdfDocument document) {
    final result = <_RawPdfField>[];

    try {
      final fields = document.form.fields;
      for (var i = 0; i < fields.count; i++) {
        final field = fields[i];
        final name = (field.name ?? '').trim();
        final mappingName = field.mappingName.trim();
        final page = field.page == null ? 0 : document.pages.indexOf(field.page!);

        if (field is PdfTextBoxField) {
          final value = field.text.trim();
          if (value.isNotEmpty && value != 'false') {
            result.add(_RawPdfField(
              name: name,
              mappingName: mappingName,
              value: value,
              kind: _RawPdfFieldKind.text,
              page: page < 0 ? 0 : page,
            ));
          }
        } else if (field is PdfCheckBoxField) {
          result.add(_RawPdfField(
            name: name,
            mappingName: mappingName,
            value: field.isChecked ? 'true' : 'false',
            kind: _RawPdfFieldKind.checkbox,
            page: page < 0 ? 0 : page,
          ));
        }
      }
    } catch (e) {
      throw PdfImportException('Не удалось прочитать AcroForm: $e');
    }

    return result;
  }

  /// Adaptive PDF parser.
  ///
  /// AcroForm remains the authoritative first source. When there are no
  /// usable AcroForm fields, OCR is used as a separate fallback. The OCR path
  /// never reads the PDF text layer and never uses coordinates.
  Future<PdfImportDraft> parseAdaptive(Uint8List bytes) async {
    if (bytes.length < 4 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
      throw const PdfImportException('Файл не похож на PDF.');
    }

    final document = PdfDocument(inputBytes: bytes);
    List<_RawPdfField> fields = const [];
    try {
      fields = _extractFormFields(document);
      if (fields.isNotEmpty) {
        return _buildDraft(fields);
      }
    } catch (e) {
      if (e is PdfImportException) {
        // A malformed/unsupported AcroForm is allowed to fall through to OCR.
        fields = const [];
      }
    } finally {
      document.dispose();
    }

    final ocrText = await PdfOcrExtractor().extract(bytes);
    return _buildOcrDraft(ocrText);
  }

  PdfImportDraft _buildDraft(List<_RawPdfField> fields) {
    final evidence = <PdfImportField>[];
    final warnings = <String>[];

    if (fields.isEmpty) {
      throw const PdfImportException(
        'В PDF не найдены доступные AcroForm-поля. Текущая версия PDF-импортёра поддерживает только данные из AcroForm.',
      );
    }

    String formValue(List<String> aliases, {String? evidenceKey}) {
      for (final alias in aliases) {
        final normalizedAlias = _normalize(alias);
        if (normalizedAlias.isEmpty) continue;

        for (final field in fields) {
          if (!_matchesField(field, normalizedAlias)) continue;
          if (field.value.trim().isEmpty || field.value == 'false') continue;

          final value = field.value.trim();
          evidence.add(PdfImportField(
            key: evidenceKey ?? alias,
            value: value,
            confidence: 0.99,
            source: 'acroform',
            page: field.page,
          ));
          return value;
        }
      }
      return '';
    }

    String firstFieldValue(List<String> aliases, {String? evidenceKey}) =>
        formValue(aliases, evidenceKey: evidenceKey);

    final classLevel = firstFieldValue(
      ['ClassLevel', 'class_level', 'classlevel', 'Class and Level'],
      evidenceKey: 'classLevel',
    );
    final parsedClass = _parseClassLevel(classLevel);

    final name = firstFieldValue(
      ['CharacterName', 'text_14uqfb', 'Character Name', 'Name'],
      evidenceKey: 'name',
    );
    if (name.isEmpty) {
      throw const PdfImportException('Не найдено имя персонажа в AcroForm.');
    }

    final race = firstFieldValue(['Race'], evidenceKey: 'race');
    final background = firstFieldValue(['Background'], evidenceKey: 'background');
    final playerName = firstFieldValue(['PlayerName', 'Player Name'], evidenceKey: 'playerName');
    final alignment = firstFieldValue(['Alignment'], evidenceKey: 'alignment');
    final xp = _parseInt(firstFieldValue(['XP'], evidenceKey: 'xp')) ?? 0;

    final copper = _currencyValue(fields, ['CP', 'Copper'], evidenceKey: 'copper', evidence: evidence);
    final silver = _currencyValue(fields, ['SP', 'Silver'], evidenceKey: 'silver', evidence: evidence);
    final electrum = _currencyValue(fields, ['EP', 'EM', 'Electrum'], evidenceKey: 'electrum', evidence: evidence);
    final gold = _currencyValue(fields, ['GP', 'Gold'], evidenceKey: 'gold', evidence: evidence);
    final platinum = _currencyValue(fields, ['PP', 'Platinum'], evidenceKey: 'platinum', evidence: evidence);

    final strength = _scoreFromFields(fields, ['STR', 'Strength', 'Strength Score'], defaultValue: 10, evidence: evidence);
    final dexterity = _scoreFromFields(fields, ['DEX', 'Dexterity', 'Dexterity Score'], defaultValue: 10, evidence: evidence);
    final constitution = _scoreFromFields(fields, ['CON', 'Constitution', 'Constitution Score'], defaultValue: 10, evidence: evidence);
    final intelligence = _scoreFromFields(fields, ['INT', 'Intelligence', 'Intelligence Score'], defaultValue: 10, evidence: evidence);
    final wisdom = _scoreFromFields(fields, ['WIS', 'Wisdom', 'Wisdom Score'], defaultValue: 10, evidence: evidence);
    final charisma = _scoreFromFields(fields, ['CHA', 'Charisma', 'Charisma Score'], defaultValue: 10, evidence: evidence);

    final maxHp = _parseInt(formValue(['HPMax', 'HP Max', 'Maximum HP', 'Max HP'], evidenceKey: 'maxHp')) ?? 10;
    final hp = _parseInt(formValue(['HPCurrent_LXTJ', 'HPCurrent', 'Current HP', 'HP Current'], evidenceKey: 'hp')) ?? maxHp;
    final tempHp = _parseInt(formValue(['HPTemp_MXBT', 'HPTemp', 'Temporary HP', 'Temp HP'], evidenceKey: 'temporaryHp')) ?? 0;
    final ac = _parseInt(formValue(['AC', 'Armor Class', 'Armour Class'], evidenceKey: 'armorClass')) ?? 10;
    final initiative = _parseSignedInt(formValue(['Initiative'], evidenceKey: 'initiative')) ?? 0;
    final speed = _parseInt(formValue(['Speed'], evidenceKey: 'speed')) ?? 30;
    final proficiencyBonus = _parseSignedInt(formValue(['ProfBonus', 'Proficiency Bonus'], evidenceKey: 'proficiencyBonus')) ?? 2;
    final inspiration = _checkboxValue(fields, ['Inspiration'], evidence: evidence);
    final hitDice = firstFieldValue(['HD', 'Hit Dice', 'HitDice'], evidenceKey: 'hitDice');

    final personality = firstFieldValue(['PersonalityTraits _25LZ', 'Personality Traits'], evidenceKey: 'personalityTraits');
    final ideals = firstFieldValue(['Ideals_KELS', 'Ideals'], evidenceKey: 'ideals');
    final bonds = firstFieldValue(['Bonds_HWGM', 'Bonds'], evidenceKey: 'bonds');
    final flaws = firstFieldValue(['Flaws_DH53', 'Flaws'], evidenceKey: 'flaws');
    final proficiencies = firstFieldValue(
      ['ProficienciesLang_OVQQ', 'Proficiencies & Languages', 'Proficiencies and Languages'],
      evidenceKey: 'proficienciesLanguages',
    );
    final equipment = firstFieldValue(['Equipment_VXRI', 'Equipment'], evidenceKey: 'equipment');
    final abilitiesText = firstFieldValue(
      ['Features and Traits_3R4V', 'Features and Traits', 'Features & Traits'],
      evidenceKey: 'featuresAndTraits',
    );

    final age = firstFieldValue(['text_8oymo', 'Age'], evidenceKey: 'age');
    final height = firstFieldValue(['text_9edkz', 'Height'], evidenceKey: 'height');
    final weight = firstFieldValue(['text_10cjuj', 'Weight'], evidenceKey: 'weight');
    final eyes = firstFieldValue(['text_11lkkm', 'Eyes'], evidenceKey: 'eyes');
    final skin = firstFieldValue(['text_12kfvu', 'Skin'], evidenceKey: 'skin');
    final hair = firstFieldValue(['text_13lzpo', 'Hair'], evidenceKey: 'hair');
    final backstory = firstFieldValue(['textarea_3wrh', 'Character Backstory', 'Backstory'], evidenceKey: 'backstory');
    final allies = firstFieldValue(['Allies and Organizations', 'Allies & Organizations', 'AlliesOrganizations'], evidenceKey: 'alliesOrganizations');
    final treasure = firstFieldValue(['textarea_5wbeq', 'Treasure'], evidenceKey: 'treasure');
    final spellAbilityRaw = firstFieldValue(
      ['SpellcastingAbility 2', 'Spellcasting Ability', 'SpellcastingAbility'],
      evidenceKey: 'spellcastingAbility',
    );

    final savingThrows = _extractSavingThrowProficiencies(fields, evidence);
    final skills = _extractSkillProficiencies(fields, evidence);

    final character = CharacterModel(
      name: name,
      race: race,
      className: parsedClass.$1,
      level: parsedClass.$2,
      background: background,
      alignment: alignment,
      playerName: playerName,
      strength: strength,
      dexterity: dexterity,
      constitution: constitution,
      intelligence: intelligence,
      wisdom: wisdom,
      charisma: charisma,
      hp: hp,
      maxHp: maxHp < hp ? hp : maxHp,
      temporaryHp: tempHp,
      armorClass: ac,
      initiative: initiative,
      speed: speed,
      proficiencyBonus: proficiencyBonus,
      inspiration: inspiration,
      hitDice: hitDice,
      savingThrowProficiencies: savingThrows,
      skillProficiencies: skills,
      xp: xp,
      copper: copper,
      silver: silver,
      electrum: electrum,
      gold: gold,
      platinum: platinum,
      spellcastingAbility: _normalizeAbility(spellAbilityRaw),
      spellcastingClass: parsedClass.$1,
      personalityTraits: personality,
      ideals: ideals,
      bonds: bonds,
      flaws: flaws,
      proficienciesLanguages: proficiencies,
      age: age,
      height: height,
      weight: weight,
      eyes: eyes,
      skin: skin,
      hair: hair,
      backstory: backstory,
      alliesOrganizations: allies,
      treasure: treasure,
    );

    if (equipment.isNotEmpty) {
      warnings.add('Снаряжение импортировано как один текстовый предмет; автоматическое разбиение на отдельные предметы будет следующим этапом.');
    }
    if (abilitiesText.isNotEmpty) {
      warnings.add('Особенности импортированы в данные персонажа как исходный текст; автоматическое разбиение на отдельные способности будет следующим этапом.');
    }

    final attacks = _extractAttacks(fields, evidence);
    final spells = _extractSpells(fields, evidence, warnings);
    final items = equipment.isEmpty
        ? const <ItemModel>[]
        : [ItemModel(characterId: 0, name: 'Снаряжение', description: equipment)];

    return PdfImportDraft(
      character: character,
      attacks: attacks,
      spells: spells,
      items: items,
      fields: evidence,
      warnings: warnings,
    );
  }

  PdfImportDraft _buildOcrDraft(String rawText) {
    final parser = _OcrTextParser(rawText);
    return parser.buildDraft();
  }

  bool _matchesField(_RawPdfField field, String normalizedAlias) {
    final names = <String>{
      _normalize(field.name),
      _normalize(field.mappingName),
    }..remove('');
    return names.any((name) => name == normalizedAlias);
  }

  int _scoreFromFields(
    List<_RawPdfField> fields,
    List<String> aliases, {
    required int defaultValue,
    required List<PdfImportField> evidence,
  }) {
    for (final alias in aliases) {
      final normalized = _normalize(alias);
      for (final field in fields) {
        if (!_matchesField(field, normalized) || field.kind != _RawPdfFieldKind.text) continue;
        final value = _parseInt(field.value);
        if (value == null || value < 1 || value > 30) continue;
        evidence.add(PdfImportField(
          key: alias,
          value: field.value.trim(),
          confidence: 0.99,
          source: 'acroform',
          page: field.page,
        ));
        return value;
      }
    }
    return defaultValue;
  }

  int _currencyValue(
    List<_RawPdfField> fields,
    List<String> aliases, {
    required String evidenceKey,
    required List<PdfImportField> evidence,
  }) {
    final raw = _findFieldValue(fields, aliases);
    if (raw == null) return 0;
    final parsed = _parseInt(raw.value) ?? 0;
    evidence.add(PdfImportField(
      key: evidenceKey,
      value: raw.value.trim(),
      confidence: 0.99,
      source: 'acroform',
      page: raw.page,
    ));
    return parsed;
  }

  bool _checkboxValue(
    List<_RawPdfField> fields,
    List<String> aliases, {
    required List<PdfImportField> evidence,
  }) {
    for (final alias in aliases) {
      final normalized = _normalize(alias);
      for (final field in fields) {
        if (field.kind != _RawPdfFieldKind.checkbox || !_matchesField(field, normalized)) continue;
        if (_isTruthy(field.value)) {
          evidence.add(PdfImportField(
            key: alias,
            value: field.value,
            confidence: 0.99,
            source: 'acroform',
            page: field.page,
          ));
        }
        return _isTruthy(field.value);
      }
    }
    return false;
  }

  Set<String> _extractSavingThrowProficiencies(
    List<_RawPdfField> fields,
    List<PdfImportField> evidence,
  ) {
    const aliases = <String, List<String>>{
      'str': ['Saving Throw STR', 'STR Saving Throw', 'SavingThrowsSTR', 'Saving Throw Strength', 'Strength Saving Throw'],
      'dex': ['Saving Throw DEX', 'DEX Saving Throw', 'SavingThrowsDEX', 'Saving Throw Dexterity', 'Dexterity Saving Throw'],
      'con': ['Saving Throw CON', 'CON Saving Throw', 'SavingThrowsCON', 'Saving Throw Constitution', 'Constitution Saving Throw'],
      'int': ['Saving Throw INT', 'INT Saving Throw', 'SavingThrowsINT', 'Saving Throw Intelligence', 'Intelligence Saving Throw'],
      'wis': ['Saving Throw WIS', 'WIS Saving Throw', 'SavingThrowsWIS', 'Saving Throw Wisdom', 'Wisdom Saving Throw'],
      'cha': ['Saving Throw CHA', 'CHA Saving Throw', 'SavingThrowsCHA', 'Saving Throw Charisma', 'Charisma Saving Throw'],
    };

    return _extractNamedCheckboxes(fields, aliases, evidence, 'savingThrow');
  }

  Set<String> _extractSkillProficiencies(
    List<_RawPdfField> fields,
    List<PdfImportField> evidence,
  ) {
    const aliases = <String, List<String>>{
      'acrobatics': ['Acrobatics Proficiency', 'Skill Acrobatics', 'Proficiency Acrobatics', 'Acrobatics'],
      'investigation': ['Investigation Proficiency', 'Skill Investigation', 'Proficiency Investigation', 'Investigation', 'Анализ'],
      'athletics': ['Athletics Proficiency', 'Skill Athletics', 'Proficiency Athletics', 'Athletics'],
      'perception': ['Perception Proficiency', 'Skill Perception', 'Proficiency Perception', 'Perception'],
      'survival': ['Survival Proficiency', 'Skill Survival', 'Proficiency Survival', 'Survival'],
      'performance': ['Performance Proficiency', 'Skill Performance', 'Proficiency Performance', 'Performance'],
      'intimidation': ['Intimidation Proficiency', 'Skill Intimidation', 'Proficiency Intimidation', 'Intimidation'],
      'history': ['History Proficiency', 'Skill History', 'Proficiency History', 'History'],
      'sleightofhand': ['Sleight of Hand Proficiency', 'Skill Sleight of Hand', 'Proficiency Sleight of Hand', 'Sleight of Hand'],
      'medicine': ['Medicine Proficiency', 'Skill Medicine', 'Proficiency Medicine', 'Medicine'],
      'deception': ['Deception Proficiency', 'Skill Deception', 'Proficiency Deception', 'Deception'],
      'nature': ['Nature Proficiency', 'Skill Nature', 'Proficiency Nature', 'Nature'],
      'arcana': ['Arcana Proficiency', 'Skill Arcana', 'Proficiency Arcana', 'Arcana'],
      'insight': ['Insight Proficiency', 'Skill Insight', 'Proficiency Insight', 'Insight'],
      'religion': ['Religion Proficiency', 'Skill Religion', 'Proficiency Religion', 'Religion'],
      'stealth': ['Stealth Proficiency', 'Skill Stealth', 'Proficiency Stealth', 'Stealth'],
      'persuasion': ['Persuasion Proficiency', 'Skill Persuasion', 'Proficiency Persuasion', 'Persuasion'],
      'animal': ['Animal Handling Proficiency', 'Skill Animal Handling', 'Proficiency Animal Handling', 'Animal Handling'],
    };

    return _extractNamedCheckboxes(fields, aliases, evidence, 'skill');
  }

  Set<String> _extractNamedCheckboxes(
    List<_RawPdfField> fields,
    Map<String, List<String>> aliases,
    List<PdfImportField> evidence,
    String evidencePrefix,
  ) {
    final result = <String>{};
    for (final entry in aliases.entries) {
      for (final alias in entry.value) {
        final normalized = _normalize(alias);
        for (final field in fields) {
          if (field.kind != _RawPdfFieldKind.checkbox || !_matchesField(field, normalized)) continue;
          if (_isTruthy(field.value)) {
            result.add(entry.key);
            evidence.add(PdfImportField(
              key: '$evidencePrefix.${entry.key}',
              value: field.value,
              confidence: 0.99,
              source: 'acroform',
              page: field.page,
            ));
          }
          break;
        }
        if (result.contains(entry.key)) break;
      }
    }
    return result;
  }

  List<AttackModel> _extractAttacks(
    List<_RawPdfField> fields,
    List<PdfImportField> evidence,
  ) {
    final byIndex = <int, Map<String, String>>{};

    for (final field in fields) {
      final names = <String>{field.name, field.mappingName};
      for (final rawName in names) {
        final name = _normalize(rawName);
        final nameMatch = RegExp(r'^WPN(?: (\d+))? NAME$').firstMatch(name) ??
            RegExp(r'^WPN NAME (\d+)$').firstMatch(name);
        if (nameMatch != null && field.value.trim().isNotEmpty) {
          final index = int.tryParse(nameMatch.group(1) ?? '1') ?? 1;
          byIndex.putIfAbsent(index, () => {})['name'] = field.value.trim();
        }

        final atk = RegExp(r'^WPN ?(\d+) ATKBONUS$').firstMatch(name);
        if (atk != null && field.value.trim().isNotEmpty) {
          final index = int.tryParse(atk.group(1) ?? '1') ?? 1;
          byIndex.putIfAbsent(index, () => {})['bonus'] = field.value.trim();
        }

        final dmg = RegExp(r'^WPN ?(\d+) DAMAGE$').firstMatch(name);
        if (dmg != null && field.value.trim().isNotEmpty) {
          final index = int.tryParse(dmg.group(1) ?? '1') ?? 1;
          byIndex.putIfAbsent(index, () => {})['damage'] = field.value.trim();
        }
      }
    }

    final attacks = <AttackModel>[];
    for (final entry in byIndex.entries.toList()..sort((a, b) => a.key.compareTo(b.key))) {
      final data = entry.value;
      final name = data['name']?.trim() ?? '';
      if (name.isEmpty) continue;
      attacks.add(AttackModel(
        characterId: 0,
        name: name,
        attackBonus: data['bonus'] ?? '',
        damage: data['damage'] ?? '',
        sortOrder: attacks.length,
      ));
    }
    return attacks;
  }

  List<SpellModel> _extractSpells(
    List<_RawPdfField> fields,
    List<PdfImportField> evidence,
    List<String> warnings,
  ) {
    final spells = <SpellModel>[];
    final seen = <String>{};

    for (final field in fields) {
      final names = <String>{field.name, field.mappingName};
      String? rawName;
      int? level;

      for (final rawFieldName in names) {
        final parsed = _parseSpellFieldName(rawFieldName);
        if (parsed == null) continue;
        rawName = parsed.$1;
        level = parsed.$2;
        break;
      }

      // Generated AcroForm fields on the standard interactive sheet use names
      // such as `Spells 1014`, `Spells 1023`, `Spells 1046`, ... . The numeric
      // suffix is an AcroForm field identifier, not page geometry. On this
      // family of sheets those identifiers form stable ranges for spell
      // levels, so we can recover the level without touching the text layer or
      // any coordinates.
      if (rawName == null) {
        final generated = _parseGeneratedSpellField(field.name);
        if (generated == null) continue;
        rawName = field.name;
        level = generated;
      }

      if (field.value.trim().isEmpty) continue;

      final raw = field.value.trim();
      final parts = raw.split(' - ');
      final name = parts.first.trim();
      if (name.isEmpty) continue;

      final normalizedName = _normalize(name);
      if (!seen.add(normalizedName)) continue;

      if (level == null) {
        warnings.add('Заклинание "$name" найдено в AcroForm, но уровень не указан в имени поля; оно не импортировано автоматически.');
        continue;
      }

      spells.add(SpellModel(
        characterId: 0,
        name: name,
        sourceUrl: parts.length > 1 ? parts.sublist(1).join(' - ').trim() : '',
        level: level,
      ));
      evidence.add(PdfImportField(
        key: 'spell',
        value: name,
        confidence: 0.99,
        source: 'acroform',
        page: field.page,
      ));

      if (spells.length >= 100) break;
    }

    return spells;
  }

  int? _parseGeneratedSpellField(String rawName) {
    final normalized = _normalize(rawName);
    final match = RegExp(r'^SPELLS (\d+)$').firstMatch(normalized);
    if (match == null) return null;

    final id = int.tryParse(match.group(1)!);
    if (id == null) return null;

    // This is the naming scheme used by the interactive character-sheet
    // AcroForm. The first spell field is `Spells 1014`; subsequent blocks are
    // `1023..1033`, `1034..1046`, etc. The ranges map directly to levels 0..9.
    const ranges = <(int, int, int)>[
      (1014, 1022, 0),
      (1023, 1033, 1),
      (1034, 1046, 2),
      (1047, 1059, 3),
      (1060, 1072, 4),
      (1073, 1081, 5),
      (1082, 1090, 6),
      (1091, 1099, 7),
      (10100, 10106, 8),
      (10107, 10113, 9),
    ];

    for (final (start, end, level) in ranges) {
      if (id >= start && id <= end) return level;
    }
    return null;
  }

  (String, int?)? _parseSpellFieldName(String rawName) {
    final normalized = _normalize(rawName);
    if (!normalized.startsWith('SPELL')) return null;

    final explicitPatterns = <RegExp>[
      RegExp(r'^SPELLS? LEVEL (\d+)(?: |$)'),
      RegExp(r'^SPELLS? LVL (\d+)(?: |$)'),
      RegExp(r'^SPELLS? L(\d+)(?: |$)'),
      RegExp(r'^SPELLS? (\d+) LEVEL(?: |$)'),
      RegExp(r'^SPELLS? (\d+) LVL(?: |$)'),
    ];

    for (final pattern in explicitPatterns) {
      final match = pattern.firstMatch(normalized);
      if (match == null) continue;
      final level = int.tryParse(match.group(1)!);
      if (level == null || level < 0 || level > 9) continue;
      return (rawName, level);
    }

    return null;
  }

  _RawPdfField? _findFieldValue(List<_RawPdfField> fields, List<String> aliases) {
    for (final alias in aliases) {
      final normalized = _normalize(alias);
      for (final field in fields) {
        if (_matchesField(field, normalized)) return field;
      }
    }
    return null;
  }

  (String, int) _parseClassLevel(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return ('', 1);

    final match = RegExp(r'^(.*?)(?:\s+)(\d+)$').firstMatch(cleaned);
    if (match == null) return (cleaned, 1);
    return (match.group(1)!.trim(), int.tryParse(match.group(2)!) ?? 1);
  }

  int? _parseInt(String raw) {
    if (raw.trim().isEmpty) return null;
    final direct = int.tryParse(raw.trim());
    if (direct != null) return direct;
    final match = RegExp(r'[-+]?\d+').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  int? _parseSignedInt(String raw) {
    if (raw.trim().isEmpty) return null;
    final match = RegExp(r'[+-]?\d+').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  bool _isTruthy(String value) {
    final normalized = _normalize(value);
    return normalized == '1' ||
        normalized == 'YES' ||
        normalized == 'TRUE' ||
        normalized == 'ДА' ||
        normalized == 'Y';
  }

  String _normalizeAbility(String raw) {
    switch (_normalize(raw)) {
      case 'XAR':
      case 'ХАР':
      case 'CHA':
      case 'ХАРИЗМА':
        return 'cha';
      case 'STR':
      case 'СИЛ':
      case 'СИЛА':
        return 'str';
      case 'DEX':
      case 'ЛОВ':
      case 'ЛОВКОСТЬ':
        return 'dex';
      case 'CON':
      case 'ТЕЛ':
      case 'ТЕЛОСЛОЖЕНИЕ':
        return 'con';
      case 'INT':
      case 'ИНТ':
      case 'ИНТЕЛЛЕКТ':
        return 'int';
      case 'WIS':
      case 'МДР':
      case 'МУДРОСТЬ':
        return 'wis';
      default:
        return raw.trim();
    }
  }

  String _normalize(String value) {
    return value
        .toUpperCase()
        .replaceAll('Ё', 'Е')
        .replaceAll(RegExp(r'[\s._\-]+'), ' ')
        .trim();
  }
}

class _OcrTextParser {
  final List<String> _lines;
  final List<PdfImportField> _evidence = [];
  final List<String> _warnings = [];

  _OcrTextParser(String rawText)
      : _lines = rawText
            .replaceAll('\r\n', '\n')
            .replaceAll('\r', '\n')
            .split('\n')
            .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false);

  PdfImportDraft buildDraft() {
    if (_lines.isEmpty) {
      throw const PdfImportException('OCR не вернул распознаваемый текст.');
    }

    final top = _extractTopMetadata();
    final structured = _extractSpecializedLayout();
    String pick(String key, String fallback) =>
        (structured[key] ?? '').trim().isNotEmpty ? structured[key]! : fallback;

    final classLevel = pick(
      'classLevel',
      top['classLevel']?.isNotEmpty == true
          ? top['classLevel']!
          : _valueForLabels([
              'КЛАСС И УРОВЕНЬ',
              'CLASS AND LEVEL',
              'CLASS LEVEL',
            ]),
    );
    final name = pick(
      'name',
      top['name']?.isNotEmpty == true
          ? top['name']!
          : _valueForLabels([
              'ИМЯ ПЕРСОНАЖА',
              'CHARACTER NAME',
              'CHARACTER',
            ], required: true),
    );
    final parsedClass = _parseClassLevel(
      classLevel.isNotEmpty ? classLevel : (top['classLevel'] ?? ''),
    );
    final ocrProficiencies = _extractOcrProficiencies();
    final spellcastingAbility = _extractSpellcastingAbility();
    final spellcastingClass = _extractSpellcastingClass();

    final character = CharacterModel(
      name: name,
      race: pick('race', top['race']?.isNotEmpty == true ? top['race']! : _valueForLabels(['РАСА', 'RACE'])),
      className: parsedClass.$1,
      level: parsedClass.$2,
      background: pick('background', top['background']?.isNotEmpty == true ? top['background']! : _valueForLabels(['ПРЕДЫСТОРИЯ', 'BACKGROUND'])),
      alignment: pick('alignment', top['alignment']?.isNotEmpty == true ? top['alignment']! : _valueForLabels(['МИРОВОЗЗРЕНИЕ', 'ALIGNMENT'])),
      playerName: pick('playerName', top['playerName']?.isNotEmpty == true ? top['playerName']! : _valueForLabels(['ИМЯ ИГРОКА', 'PLAYER NAME'])),
      strength: _parseInt(structured['strength'] ?? '') ?? _score(['СИЛА', 'STRENGTH']),
      dexterity: _parseInt(structured['dexterity'] ?? '') ?? _score(['ЛОВКОСТЬ', 'DEXTERITY']),
      constitution: _parseInt(structured['constitution'] ?? '') ?? _score(['ТЕЛОСЛОЖЕНИЕ', 'CONSTITUTION']),
      intelligence: _parseInt(structured['intelligence'] ?? '') ?? _score(['ИНТЕЛЛЕКТ', 'INTELLIGENCE']),
      wisdom: _parseInt(structured['wisdom'] ?? '') ?? _score(['МУДРОСТЬ', 'WISDOM']),
      charisma: _parseInt(structured['charisma'] ?? '') ?? _score(['ХАРИЗМА', 'CHARISMA']),
      hp: _parseInt(structured['hp'] ?? '') ?? _parseInt(top['hp'] ?? '')
              ?? _intValue(['ТЕКУЩИЕ ХИТЫ', 'CURRENT HIT POINTS', 'CURRENT HP'])
              ?? 0,
      maxHp: _parseInt(structured['maxHp'] ?? '') ?? _parseInt(top['maxHp'] ?? '')
              ?? _intValue(['МАКСИМУМ ХИТОВ', 'MAXIMUM HIT POINTS', 'MAX HP'])
              ?? 0,
      temporaryHp: _parseInt(structured['temporaryHp'] ?? '') ?? _intValue(['ВРЕМЕННЫЕ ХИТЫ', 'TEMPORARY HIT POINTS', 'TEMP HP']) ?? 0,
      armorClass: _parseInt(structured['ac'] ?? '') ?? _parseInt(top['ac'] ?? '') ?? _intValueRange(['КД', 'ARMOR CLASS', 'AC'], 1, 40) ?? 10,
      initiative: _parseSignedInt(structured['initiative'] ?? '') ?? _parseSignedInt(top['initiative'] ?? '') ?? _signedIntValueRange(['ИНИЦИАТИВА', 'INITIATIVE'], -30, 30) ?? 0,
      speed: _parseInt(structured['speed'] ?? '') ?? _parseInt(top['speed'] ?? '') ?? _intValueRange(['СКОРОСТЬ', 'SPEED'], 0, 120) ?? 30,
      proficiencyBonus: _parseSignedInt(structured['proficiencyBonus'] ?? '')
              ?? _signedIntValueRange(['БОНУС МАСТЕРСТВА', 'PROFICIENCY BONUS'], -20, 20)
              ?? _parseSignedInt(top['proficiencyBonus'] ?? '')
              ?? _derivedProficiencyBonus(parsedClass.$2),
      inspiration: false,
      hitDice: (structured['hitDice'] ?? '').isNotEmpty ? structured['hitDice']! : _extractHitDice(),
      savingThrowProficiencies: ocrProficiencies.$1,
      skillProficiencies: ocrProficiencies.$2,
      xp: _parseInt(structured['xp'] ?? '') ?? _intValueRange(['ОПЫТ', 'ОЧКИ ОПЫТА', 'EXPERIENCE POINTS', 'XP'], 0, 1000000000)
              ?? _parseInt(top['xp'] ?? '')
              ?? 0,
      copper: _parseInt(structured['cp'] ?? '') ?? _parseInt(top['cp'] ?? '') ?? _currency(['ММ', 'CP']),
      silver: _parseInt(structured['sp'] ?? '') ?? _parseInt(top['sp'] ?? '') ?? _currency(['СМ', 'SP']),
      electrum: _parseInt(structured['ep'] ?? '') ?? _parseInt(top['ep'] ?? '') ?? _currency(['ЭМ', 'EM', 'EP']),
      gold: _parseInt(structured['gp'] ?? '') ?? _parseInt(top['gp'] ?? '') ?? _currency(['ЗМ', 'GP', 'GOLD']),
      platinum: _parseInt(structured['pp'] ?? '') ?? _parseInt(top['pp'] ?? '') ?? _currency(['ПМ', 'PP', 'PLATINUM']),
      spellcastingAbility: spellcastingAbility.isNotEmpty
          ? spellcastingAbility
          : _normalizeAbility(_valueForLabels([
              'БАЗОВАЯ ХАРАКТЕРИСТИКА ЗАКЛИНАНИЙ',
              'SPELLCASTING ABILITY',
            ])),
      spellcastingClass: spellcastingClass,
      personalityTraits: structured['personality'] ?? _sectionAfter([
        'ЧЕРТЫ ХАРАКТЕРА',
        'PERSONALITY TRAITS',
      ]),
      ideals: structured['ideals'] ?? _sectionAfter(['ИДЕАЛЫ', 'IDEALS']),
      bonds: structured['bonds'] ?? _sectionAfter(['ПРИВЯЗАННОСТИ', 'BONDS']),
      flaws: structured['flaws'] ?? _sectionAfter(['СЛАБОСТИ', 'FLAWS']),
      proficienciesLanguages: structured['proficiencies'] ?? _sectionAfter([
        'ПРОЧИЕ ВЛАДЕНИЯ И ЯЗЫКИ',
        'PROFICIENCIES AND LANGUAGES',
      ]),
      age: (structured['age'] ?? '').isNotEmpty ? structured['age']! : _valueForLabels(['ВОЗРАСТ', 'AGE']),
      height: (structured['height'] ?? '').isNotEmpty ? structured['height']! : _valueForLabels(['РОСТ', 'HEIGHT']),
      weight: (structured['weight'] ?? '').isNotEmpty ? structured['weight']! : _valueForLabels(['ВЕС', 'WEIGHT']),
      eyes: _valueForLabels(['ГЛАЗА', 'EYES']),
      skin: _valueForLabels(['КОЖА', 'SKIN']),
      hair: _valueForLabels(['ВОЛОСЫ', 'HAIR']),
      backstory: structured['backstory'] ?? _sectionAfter(['ПРЕДЫСТОРИЯ ПЕРСОНАЖА', 'CHARACTER BACKSTORY']),
      alliesOrganizations: structured['allies'] ?? _sectionAfter([
        'СОЮЗНИКИ И ОРГАНИЗАЦИИ',
        'ALLIES AND ORGANIZATIONS',
      ]),
      treasure: structured['treasure'] ?? _sectionAfter(['СОКРОВИЩА', 'TREASURE']),
    );

    final equipment = structured['equipment'] ?? _sectionAfter(['СНАРЯЖЕНИЕ', 'EQUIPMENT']);
    if (equipment.isNotEmpty) {
      _warnings.add('Снаряжение найдено OCR как текстовый блок и импортировано одним предметом.');
    }
    _warnings.add('OCR импорт работает без координат: сомнительные поля следует проверить перед сохранением.');
    _warnings.add('Навыки и спасброски не отмечаются автоматически по OCR, потому что отметки proficiency не всегда распознаются как текст.');

    return PdfImportDraft(
      character: character,
      attacks: _extractAttacks(),
      spells: _extractSpells(),
      items: equipment.isEmpty
          ? const <ItemModel>[]
          : [ItemModel(characterId: 0, name: 'Снаряжение', description: equipment)],
      fields: _evidence,
      warnings: _warnings,
    );
  }

  (Set<String>, Set<String>) _extractOcrProficiencies() {
    final values = <int>[];
    for (final line in _lines) {
      final trimmed = line.trim();
      if (RegExp(r'^[+-]?\s*\d{1,2}$').hasMatch(trimmed)) {
        final value = _parseSignedInt(trimmed);
        if (value != null) values.add(value);
        if (values.length >= 30) break;
      } else if (values.isNotEmpty) {
        // The first numeric run belongs to the ability modifiers, saving
        // throws, and skills on this sheet. Stop once text begins.
        break;
      }
    }

    final saves = <String>{};
    final skills = <String>{};
    if (values.length < 12) return (saves, skills);

    const saveNames = ['strength', 'dexterity', 'constitution', 'intelligence', 'wisdom', 'charisma'];
    const skillNames = [
      'acrobatics', 'analysis', 'athletics', 'perception', 'survival', 'performance',
      'intimidation', 'history', 'sleightofhand', 'arcana', 'medicine', 'deception',
      'nature', 'insight', 'religion', 'stealth', 'persuasion', 'animal',
    ];
    final abilityMods = values.take(6).toList();
    final saveTotals = values.skip(6).take(6).toList();
    final skillTotals = values.skip(12).take(18).toList();
    const skillAbility = ['dex', 'int', 'str', 'wis', 'wis', 'cha', 'cha', 'int', 'dex', 'int', 'wis', 'cha', 'int', 'wis', 'int', 'dex', 'cha', 'wis'];
    const abilityIndex = {'str': 0, 'dex': 1, 'con': 2, 'int': 3, 'wis': 4, 'cha': 5};

    // Infer the proficiency bonus from the arithmetic relationship between
    // ability modifiers, saving throws, and skill totals. We do not need any
    // coordinates or template positions for this: choose the 2..6 value that
    // explains the largest number of totals exactly.
    int proficiencyBonus = 0;
    var bestMatches = 0;
    for (var candidate = 2; candidate <= 6; candidate++) {
      var matches = 0;
      for (var i = 0; i < saveTotals.length; i++) {
        if (saveTotals[i] == abilityMods[i] + candidate) matches++;
      }
      for (var i = 0; i < skillTotals.length && i < skillNames.length; i++) {
        final base = abilityMods[abilityIndex[skillAbility[i]]!];
        if (skillTotals[i] == base + candidate) matches++;
      }
      if (matches > bestMatches) {
        bestMatches = matches;
        proficiencyBonus = candidate;
      }
    }
    if (bestMatches < 2) return (saves, skills);

    for (var i = 0; i < saveNames.length && i < saveTotals.length; i++) {
      if (saveTotals[i] == abilityMods[i] + proficiencyBonus) saves.add(saveNames[i]);
    }
    for (var i = 0; i < skillNames.length && i < skillTotals.length; i++) {
      final base = abilityMods[abilityIndex[skillAbility[i]]!];
      if (skillTotals[i] == base + proficiencyBonus) skills.add(skillNames[i]);
    }
    return (saves, skills);
  }

  String _extractSpellcastingAbility() {
    final anchor = _indexOfLabel(['КЛАСС ЗАКЛИНАТЕЛЯ', 'SPELLCASTING CLASS']);
    final from = anchor >= 0 ? anchor + 1 : (_lines.length > 230 ? _lines.length - 50 : 0);
    final to = anchor >= 0 ? (anchor + 20).clamp(0, _lines.length) : _lines.length;
    for (var i = from; i < to; i++) {
      final normalized = _normalize(_lines[i]);
      if (normalized == 'ХАР' || normalized == 'ХАРИЗМА' || normalized == 'CHA' || normalized == 'CHARISMA') return 'cha';
      if (normalized == 'СИЛ' || normalized == 'СИЛА' || normalized == 'STR') return 'str';
      if (normalized == 'ЛОВ' || normalized == 'ЛОВКОСТЬ' || normalized == 'DEX') return 'dex';
      if (normalized == 'ИНТ' || normalized == 'ИНТЕЛЛЕКТ' || normalized == 'INT') return 'int';
      if (normalized == 'МДР' || normalized == 'МУДРОСТЬ' || normalized == 'WIS') return 'wis';
    }
    return '';
  }

  String _extractSpellcastingClass() {
    final anchor = _indexOfLabel(['КЛАСС ЗАКЛИНАТЕЛЯ', 'SPELLCASTING CLASS']);
    if (anchor < 0) return '';
    for (var i = anchor + 1; i < _lines.length && i < anchor + 8; i++) {
      final candidate = _lines[i].trim();
      if (candidate.isEmpty || _isLikelySectionHeader(candidate) || _normalize(candidate).contains('ИЗВЕСТНЫЕ ЗАКЛИНАНИЯ')) continue;
      if (_looksLikeStandaloneNumber(candidate)) continue;
      return candidate;
    }
    return '';
  }

  String _extractHitDice() {
    final anchor = _indexOfLabel(['КОСТЬ ХИТОВ', 'HIT DICE']);
    if (anchor < 0) return '';
    for (var i = anchor; i < _lines.length && i < anchor + 8; i++) {
      final match = RegExp(r'\b\d+\s*[кk]\s*\d+\b').firstMatch(_lines[i]);
      if (match != null) return match.group(0)!.replaceAll(' ', '');
    }
    return '';
  }

  Map<String, String> _extractSpecializedLayout() {
    final result = <String, String>{};

    String? lineContaining(String token, {int from = 0, int to = -1}) {
      final n = _normalize(token);
      final end = to < 0 ? _lines.length : to.clamp(0, _lines.length);
      for (var i = from.clamp(0, _lines.length); i < end; i++) {
        if (_normalize(_lines[i]).contains(n)) return _lines[i];
      }
      return null;
    }

    // The specialized first-page top block is commonly emitted by OCR in three rows:
    // `Воин 20`, `Награждённый ewan.kowaleov`, and
    // `Калогном Калогном Аасимар-каратель Хаотично-Добрый 356000`.
    for (var i = 0; i < _lines.length && i < 140; i++) {
      final line = _lines[i].trim();
      final match = RegExp(r'^(.+?)\s+(\d{1,2})$').firstMatch(line);
      if (match != null) {
        final level = int.tryParse(match.group(2)!);
        if (level != null && level >= 1 && level <= 20) {
          result['classLevel'] = line;
          break;
        }
      }
    }

    for (var i = 0; i < _lines.length && i < 140; i++) {
      final line = _lines[i];
      final handle = RegExp(r'\b[A-Za-z][A-Za-z0-9_.-]{3,}\b').firstMatch(line);
      if (handle == null) continue;
      final token = handle.group(0)!;
      if (token.toLowerCase().contains('games')) continue;
      if (token.toLowerCase().contains('dungeons') || token.toLowerCase() == 'online') continue;
      result['playerName'] = token;
      final before = line.substring(0, handle.start).trim();
      if (before.isNotEmpty && before.length <= 50) {
        final cleaned = before.replaceAll(RegExp(r'^[|:•·]+|[|:•·]+$'), '').trim();
        if (_isPlausibleName(cleaned)) result['background'] = cleaned;
      }
      break;
    }

    // Decode the single top-row OCR line around alignment + XP.
    for (final line in _lines.take(140)) {
      final alignment = _extractAlignment(line);
      if (alignment.isEmpty) continue;
      result['alignment'] = alignment;
      final xpMatch = RegExp(r'(\d{3,9})\s*$').firstMatch(line.trim());
      if (xpMatch != null) result['xp'] = xpMatch.group(1)!;
      final normalizedLine = _normalize(line);
      final normalizedAlignment = _normalize(alignment);
      final alignmentIndex = normalizedLine.indexOf(normalizedAlignment);
      final prefix = alignmentIndex >= 0 ? normalizedLine.substring(0, alignmentIndex).trim() : '';
      final cleanedPrefix = prefix.replaceFirst(RegExp(r'\b\d{3,9}\s*$'), '').trim();
      final words = cleanedPrefix.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
      if (words.length >= 3) {
        // In this family the first two tokens are duplicated character name,
        // everything between the duplicate name and alignment is race.
        if (words.length >= 2 && _normalize(words[0]) == _normalize(words[1])) {
          result['name'] = words[0];
          result['race'] = words.sublist(2).join(' ').trim();
        } else {
          result['name'] ??= words.first;
          result['race'] ??= words.sublist(1).join(' ').trim();
        }
      }
    }

    // Page-one ability scores are frequently preserved as one six-number OCR row.
    for (final line in _lines.take(150)) {
      final values = _numberCandidates(line);
      if (values.length != 6) continue;
      if (values.every((v) => v >= 1 && v <= 30)) {
        result['strength'] = values[0].toString();
        result['dexterity'] = values[1].toString();
        result['constitution'] = values[2].toString();
        result['intelligence'] = values[3].toString();
        result['wisdom'] = values[4].toString();
        result['charisma'] = values[5].toString();
        break;
      }
    }

    // Combat row in this sheet is `18 3 40` and is unambiguous within the
    // first page. Prefer the row immediately after the ability block.
    for (final line in _lines.take(160)) {
      final values = _numberCandidates(line);
      if (values.length != 3) continue;
      if (values[0] >= 10 && values[0] <= 40 && values[1] >= -20 && values[1] <= 20 && values[2] >= 0 && values[2] <= 120) {
        result['ac'] = values[0].toString();
        result['initiative'] = values[1].toString();
        result['speed'] = values[2].toString();
        break;
      }
    }

    // HP block is normally followed by the current and temporary values.
    final hpLine = lineContaining('МАКСИМУМ ХИТОВ');
    if (hpLine != null) {
      final idx = _lines.indexOf(hpLine);
      for (final j in <int>[idx, idx + 1, idx + 2, idx + 3]) {
        if (j < 0 || j >= _lines.length) continue;
        final value = _parseInt(_lines[j]);
        if (value != null && value > 20) {
          result['maxHp'] = value.toString();
          if ((result['hp'] ?? '').isEmpty) result['hp'] = value.toString();
          break;
        }
      }
    }
    if ((result['maxHp'] ?? '').isEmpty) {
      for (final line in _lines.take(160)) {
        final n = _numberCandidates(line);
        if (n.length == 3 && n[0] > 100 && n[0] == n[1] && n[2] <= 20) {
          result['maxHp'] = n[0].toString();
          result['hp'] = n[1].toString();
          result['temporaryHp'] = n[2].toString();
          break;
        }
      }
    }

    // Currency appears as a five-number row. On this sheet it is `0 0 0 1300 0`.
    for (final line in _lines.skip(100).take(120)) {
      final values = _numberCandidates(line);
      if (values.length == 5 && values.every((v) => v >= 0 && v <= 1000000000)) {
        result['cp'] = values[0].toString();
        result['sp'] = values[1].toString();
        result['ep'] = values[2].toString();
        result['gp'] = values[3].toString();
        result['pp'] = values[4].toString();
        break;
      }
    }

    // Page-two personal data: the first clean numeric triple after the AGE/
    // HEIGHT/WEIGHT labels is age, height, weight respectively.
    final profileAnchor = _indexOfLabel(['ВОЗРАСТ', 'AGE']);
    if (profileAnchor >= 0) {
      for (var j = profileAnchor; j < _lines.length && j < profileAnchor + 30; j++) {
        final vals = RegExp(r'\b\d{1,3}(?:[,.]\d+)?\b').allMatches(_lines[j]);
        if (vals.length == 3) {
          final a = vals.elementAt(0).group(0)!;
          final h = vals.elementAt(1).group(0)!;
          final w = vals.elementAt(2).group(0)!;
          final age = double.tryParse(a.replaceAll(',', '.'));
          final height = double.tryParse(h.replaceAll(',', '.'));
          final weight = double.tryParse(w.replaceAll(',', '.'));
          if (age != null && height != null && weight != null && age >= 1 && age <= 200 && height >= 50 && height <= 300 && weight >= 20 && weight <= 400) {
            result['age'] = a;
            result['height'] = h;
            result['weight'] = w;
            break;
          }
        }
      }
    }

    // The four roleplay blocks appear after the combat row in OCR order. Use
    // strong Russian starts to avoid treating feature descriptions as flaws.
    final text = _lines.skip(100).take(70).toList();
    String collectFrom(String startText, String? stopText) {
      final startIdx = text.indexWhere((x) => x.contains(startText));
      if (startIdx < 0) return '';
      final stopIdx = stopText == null ? text.length : text.indexWhere((x) => x.contains(stopText), startIdx + 1);
      final end = stopIdx < 0 ? text.length : stopIdx;
      return text.sublist(startIdx, end).join(' ').trim();
    }
    result['personality'] = collectFrom('Правильные ответы', 'Независимость');
    result['ideals'] = collectFrom('Независимость', 'Те, кто');
    result['bonds'] = collectFrom('Те, кто', 'Я мало');
    result['flaws'] = collectFrom('Я мало', 'Доспехи:');
    result.addAll(_extractSpecializedLongSections());

    return result;
  }

  Map<String, String> _extractSpecializedLongSections() {
    final result = <String, String>{};

    final profile = _indexOfLabel(['ВОЗРАСТ', 'AGE']);
    var pageTwoStart = profile >= 0 ? profile : 0;
    while (pageTwoStart < _lines.length && !_normalize(_lines[pageTwoStart]).contains('НАЗВАНИЕ')) {
      pageTwoStart++;
    }

    // Backstory is the long-form block after the page-two metadata row.
    if (pageTwoStart >= 0 && pageTwoStart < _lines.length) {
      for (var i = pageTwoStart; i < _lines.length; i++) {
        final n = _normalize(_lines[i]);
        if (n.contains('ПРЕДЫСТОРИЯ ПЕРСОНАЖА')) {
          final parts = <String>[];
          for (var j = i + 1; j < _lines.length && j < i + 70; j++) {
            final line = _lines[j];
            final nn = _normalize(line);
            if (nn.contains('ВТОРОЕ ДЫХАНИЕ') || nn.contains('ВСПЛЕСК ДЕЙСТВИЙ') || nn.contains('ДОПОЛНИТЕЛЬНЫЕ УМЕНИЯ И ОСОБЕННОСТИ')) break;
            if (_looksLikePageFooter(line) || _isLikelySectionHeader(line)) continue;
            if (_isProfileMetadata(line)) continue;
            if (line.length >= 8) parts.add(line);
          }
          final value = parts.join(' ').trim();
          if (value.isNotEmpty) result['backstory'] = value;
          break;
        }
      }
    }

    // Proficiencies live after the combat/roleplay values, not immediately
    // after the header as OCR reading order suggests.
    for (var i = 0; i < _lines.length; i++) {
      if (!_normalize(_lines[i]).contains('ДОСПЕХИ:')) continue;
      final parts = <String>[];
      for (var j = i; j < _lines.length && j < i + 10; j++) {
        final line = _lines[j];
        if (_normalize(line).contains('СНАРЯЖЕНИЕ')) break;
        if (line.length >= 4 && !_looksLikePageFooter(line)) parts.add(line);
      }
      result['proficiencies'] = parts.join(' ').trim();
      break;
    }

    // Equipment values follow the five-currency row in OCR reading order.
    var currencyRow = -1;
    for (var i = 100; i < _lines.length; i++) {
      final values = _numberCandidates(_lines[i]);
      if (values.length == 5 && values.every((v) => v >= 0)) {
        currencyRow = i;
        break;
      }
    }
    if (currencyRow >= 0) {
      final parts = <String>[];
      for (var j = currencyRow + 1; j < _lines.length && j < currencyRow + 24; j++) {
        final line = _lines[j];
        final n = _normalize(line);
        if (n.contains('ИСПОЛЬЗОВАНИЕ ДВУХ ОРУЖИЙ') || n.contains('УДАР ВЕЛИКАНОВ') || n.contains('КОВАРСТВО ОБЛАЧНОГО ВЕЛИКАНА')) break;
        if (_looksLikePageFooter(line)) continue;
        if (_isLikelySectionHeader(line)) continue;
        if (line.length >= 4) parts.add(line);
      }
      result['equipment'] = parts.join(' ').trim();
    }

    return result;
  }

  bool _looksLikePageFooter(String line) {
    final n = _normalize(line);
    return n.contains('TM ©') || n.contains('ONLINE CHARACTER SHEET');
  }

  bool _isProfileMetadata(String line) {
    final n = _normalize(line);
    const labels = ['ИМЯ ПЕРСОНАЖА', 'ГЛАЗА', 'ВОЗРАСТ', 'ВЫСОТА', 'ВЕС', 'КОЖА', 'ВОЛОСЫ', 'НАЗВАНИЕ', 'СОКРОВИЩА', 'ВНЕШНОСТЬ ПЕРСОНАЖА', 'СИМВОЛ'];
    return labels.any((x) => n == x || n.contains(x));
  }

  Map<String, String> _extractTopMetadata() {
    final result = <String, String>{};

    for (var i = 0; i < _lines.length && i < 30; i++) {
      final line = _lines[i].trim();
      final norm = _normalize(line);
      if (norm.isEmpty) continue;

      // A common OCR form for the top metadata is a row like:
      // `Воин 20`, followed by `Аасимар-каратель Хаотично-Добрый 356000`.
      final classMatch = RegExp(r'^(.+?)\s+(\d{1,2})$').firstMatch(line);
      if (classMatch != null &&
          !_isKnownLabel(classMatch.group(1)!) &&
          !_isLikelySectionHeader(classMatch.group(1)!)) {
        final level = int.tryParse(classMatch.group(2)!);
        if (level != null && level >= 1 && level <= 20 && (result['classLevel'] ?? '').isEmpty) {
          result['classLevel'] = line;
        }
      }

      final xpMatch = RegExp(r'^(.*?)\s+(.*?)\s+(\d{3,9})$').firstMatch(line);
      if (xpMatch != null) {
        final xp = int.tryParse(xpMatch.group(3)!);
        if (xp != null && xp >= 0) {
          result['xp'] = xp.toString();
          final left = xpMatch.group(1)!.trim();
          final mid = xpMatch.group(2)!.trim();
          if (left.isNotEmpty && _isPlausibleName(left)) result.putIfAbsent('name', () => left);
          if (mid.isNotEmpty && _isPlausibleRace(mid)) result.putIfAbsent('race', () => mid);
          if (norm.contains('ХАОТИЧ') || norm.contains('ДОБР') || norm.contains('CHAOTIC')) {
            result['alignment'] = mid.isNotEmpty ? mid : result['alignment'] ?? '';
          }
        }
      }
    }

    // Look for the strongest standalone character-name candidate near its label.
    final nameIndex = _indexOfLabel(['ИМЯ ПЕРСОНАЖА', 'CHARACTER NAME']);
    if (nameIndex >= 0) {
      for (final j in <int>[nameIndex - 1, nameIndex + 1, nameIndex - 2, nameIndex + 2]) {
        if (j < 0 || j >= _lines.length) continue;
        final candidate = _lines[j].trim();
        if (_isPlausibleName(candidate) && !_isKnownLabel(candidate)) {
          result['name'] = candidate;
          break;
        }
      }
    }

    // When OCR combines the four top fields on one row, recover alignment from
    // a value line containing a known alignment word.
    for (final line in _lines.take(40)) {
      final normalized = _normalize(line);
      if (_containsAny(normalized, ['ХАОТИЧНО-ДОБРЫЙ', 'ХАОТИЧНЫЙ ДОБРЫЙ', 'CHAOTIC GOOD'])) {
        final alignment = _extractAlignment(line);
        if (alignment.isNotEmpty) result['alignment'] = alignment;
      }
    }

    // Prefer a handle that is explicitly paired with the background field.
    for (final line in _lines.take(140)) {
      if (!_normalize(line).contains('НАГРАЖДЕННЫЙ') && !_normalize(line).contains('НАГРАЖДЕН') && !_normalize(line).contains('BACKGROUND')) continue;
      final handle = RegExp(r'\b[A-Za-z][A-Za-z0-9_.-]{3,}\b').firstMatch(line);
      if (handle != null) {
        result['playerName'] = handle.group(0)!;
        final before = line.substring(0, handle.start).trim();
        if (before.isNotEmpty && before.length <= 50) result['background'] = before;
        break;
      }
    }

    // A player handle is often the easiest top-field anchor because it is an
    // ASCII username such as `ewan.kowaleov`. When it appears next to the
    // background value, recover both without relying on page geometry.
    for (final line in _lines.take(35)) {
      final handle = RegExp(r'\b[A-Za-z][A-Za-z0-9_.-]{3,}\b').firstMatch(line);
      if (handle == null) continue;
      final token = handle.group(0)!;
      if (token.toLowerCase().contains('games')) continue;
      if ((result['playerName'] ?? '').isEmpty) result['playerName'] = token;
      final before = line.substring(0, handle.start).trim();
      if ((result['background'] ?? '').isEmpty && before.length >= 3 && before.length <= 40) {
        final cleaned = before.replaceAll(RegExp(r'^[|:•·]+|[|:•·]+$'), '').trim();
        if (_isPlausibleName(cleaned)) result['background'] = cleaned;
      }
      break;
    }

    // Background is especially ambiguous on OCR because it can sit next to the
    // alignment header. Prefer a nearby value containing text rather than a label.
    if ((result['background'] ?? '').isEmpty) {
      final backgroundIndex = _indexOfLabel(['ПРЕДЫСТОРИЯ', 'BACKGROUND']);
      if (backgroundIndex >= 0) {
        for (final j in <int>[backgroundIndex + 1, backgroundIndex - 1, backgroundIndex + 2]) {
          if (j < 0 || j >= _lines.length) continue;
          final candidate = _lines[j].trim();
          if (_isPlausibleName(candidate) && !_isKnownLabel(candidate) && !_isLikelySectionHeader(candidate)) {
            result['background'] = candidate;
            break;
          }
        }
      }
    }

    final combat = _extractCombatRow();
    result.addAll(combat);

    final currency = _extractCurrencyRow();
    result.addAll(currency);

    return result;
  }

  int _derivedProficiencyBonus(int level) {
    if (level <= 0) return 2;
    return 2 + ((level - 1) ~/ 4);
  }

  Map<String, String> _extractCombatRow() {
    for (final line in _lines.take(160)) {
      final values = _numberCandidates(line);
      if (values.length < 3 || values.length > 4) continue;
      final ac = values.firstWhere((value) => value >= 10 && value <= 40, orElse: () => -1);
      if (ac < 0) continue;
      final candidates = values.where((value) => value != ac).toList();
      if (candidates.isEmpty) continue;
      final initiative = candidates.firstWhere((value) => value >= -20 && value <= 20, orElse: () => -999);
      final speed = candidates.firstWhere((value) => value >= 0 && value <= 120 && value != initiative, orElse: () => -999);
      if (initiative == -999 || speed == -999) continue;
      return {
        'ac': ac.toString(),
        'initiative': initiative.toString(),
        'speed': speed.toString(),
      };
    }
    return const {};
  }

  Map<String, String> _extractCurrencyRow() {
    for (final line in _lines.take(180)) {
      final values = _numberCandidates(line);
      if (values.length != 5) continue;
      if (values.any((value) => value < 0 || value > 1000000000)) continue;
      return {
        'cp': values[0].toString(),
        'sp': values[1].toString(),
        'ep': values[2].toString(),
        'gp': values[3].toString(),
        'pp': values[4].toString(),
      };
    }
    return const {};
  }

  bool _isPlausibleName(String value) {
    final normalized = _normalize(value);
    if (normalized.length < 2 || normalized.length > 50) return false;
    if (_isKnownLabel(value) || _isLikelySectionHeader(value)) return false;
    if (RegExp(r'^[-+]?\d+(?:[,.]\d+)?$').hasMatch(normalized)) return false;
    return RegExp(r'[A-ZА-ЯЁ][A-ZА-ЯЁa-zа-яё]').hasMatch(value);
  }

  bool _isPlausibleRace(String value) {
    final normalized = _normalize(value);
    if (normalized.length < 3 || normalized.length > 50) return false;
    return !_isKnownLabel(value) && !_isLikelySectionHeader(value) && !RegExp(r'\d{4,}').hasMatch(value);
  }

  bool _containsAny(String value, List<String> candidates) =>
      candidates.any((candidate) => value.contains(_normalize(candidate)));

  String _extractAlignment(String line) {
    final normalized = _normalize(line);
    const mappings = <String, String>{
      'ЗАКОННЫЙ ДОБРЫЙ': 'Законно-Добрый',
      'НЕЙТРАЛЬНЫЙ ДОБРЫЙ': 'Нейтрально-Добрый',
      'ХАОТИЧНЫЙ ДОБРЫЙ': 'Хаотично-Добрый',
      'ХАОТИЧНО ДОБРЫЙ': 'Хаотично-Добрый',
      'ЗАКОННЫЙ НЕЙТРАЛЬНЫЙ': 'Законно-Нейтральный',
      'ИСТИННО НЕЙТРАЛЬНЫЙ': 'Истинно-Нейтральный',
      'ХАОТИЧНЫЙ НЕЙТРАЛЬНЫЙ': 'Хаотично-Нейтральный',
      'ЗАКОННЫЙ ЗЛОЙ': 'Законно-Злой',
      'НЕЙТРАЛЬНЫЙ ЗЛОЙ': 'Нейтрально-Злой',
      'ХАОТИЧНЫЙ ЗЛОЙ': 'Хаотично-Злой',
      'ХАОТИЧНО ЗЛОЙ': 'Хаотично-Злой',
      'LAWFUL GOOD': 'Lawful Good',
      'NEUTRAL GOOD': 'Neutral Good',
      'CHAOTIC GOOD': 'Chaotic Good',
      'LAWFUL NEUTRAL': 'Lawful Neutral',
      'TRUE NEUTRAL': 'True Neutral',
      'CHAOTIC NEUTRAL': 'Chaotic Neutral',
      'LAWFUL EVIL': 'Lawful Evil',
      'NEUTRAL EVIL': 'Neutral Evil',
      'CHAOTIC EVIL': 'Chaotic Evil',
    };
    for (final entry in mappings.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    return '';
  }

  int _indexOfLabel(List<String> labels) {
    final normalized = labels.map(_normalize).toList();
    for (var i = 0; i < _lines.length; i++) {
      final line = _normalize(_lines[i]);
      if (normalized.any((label) => _containsLabel(line, label))) return i;
    }
    return -1;
  }

  bool _looksLikeStandaloneNumber(String value) => RegExp(r'^[+-]?\d+(?:[,.]\d+)?$').hasMatch(value.trim());

  bool _isNumericFieldLabel(String value) {
    final n = _normalize(value);
    const numeric = {
      'ОПЫТ', 'ОЧКИ ОПЫТА', 'XP', 'AC', 'КД', 'ИНИЦИАТИВА', 'INITIATIVE',
      'СКОРОСТЬ', 'SPEED', 'БОНУС МАСТЕРСТВА', 'PROFICIENCY BONUS',
    };
    return numeric.contains(n);
  }

  String _valueForLabels(List<String> labels, {bool required = false}) {
    final normalizedLabels = labels.map(_normalize).where((x) => x.isNotEmpty).toList();
    for (var i = 0; i < _lines.length; i++) {
      final line = _normalize(_lines[i]);
      final label = normalizedLabels.firstWhere(
        (candidate) => _containsLabel(line, candidate),
        orElse: () => '',
      );
      if (label.isEmpty) continue;

      final raw = _valueAfterLabel(_lines[i], label);
      if (raw.isNotEmpty && !_looksLikeUiLabel(raw) && !_isKnownLabel(raw)) {
        _record(label, raw, 0.80, i);
        return raw;
      }

      // OCR commonly places the field value immediately before the label in
      // decorative sheets. Search both directions while rejecting other UI
      // labels and section headings.
      for (final j in <int>[i - 1, i + 1, i - 2, i + 2, i - 3, i + 3]) {
        if (j < 0 || j >= _lines.length) continue;
        final candidate = _lines[j].trim();
        if (candidate.isEmpty || _looksLikeUiLabel(candidate)) continue;
        if (_isLikelySectionHeader(candidate) || _isKnownLabel(candidate)) continue;
        if (_looksLikeStandaloneNumber(candidate) && labels.any(_isNumericFieldLabel)) {
          // Numeric fields are handled by _intValueRange / _score below.
          continue;
        }
        _record(label, candidate, 0.72, j);
        return candidate;
      }
    }

    if (required) {
      throw const PdfImportException('OCR не удалось определить имя персонажа.');
    }
    return '';
  }

  int _score(List<String> labels) {
    final labelSet = labels.map(_normalize).toSet();
    for (var i = 0; i < _lines.length; i++) {
      final norm = _normalize(_lines[i]);
      if (!labelSet.any((label) => _containsLabel(norm, label))) continue;

      // Character sheets often print the score on the line immediately before
      // the ability name and its modifier on the same line. Prefer a plausible
      // score close to the label over the modifier.
      final candidateIndexes = <int>[i, i - 1, i + 1, i - 2, i + 2, i - 3, i + 3];
      for (final j in candidateIndexes) {
        if (j < 0 || j >= _lines.length) continue;
        for (final value in _numberCandidates(_lines[j])) {
          if (value >= 1 && value <= 30) {
            _record(labels.first, value.toString(), 0.78, j);
            return value;
          }
        }
      }
    }
    return 10;
  }

  int? _intValue(List<String> labels) {
    final value = _valueForLabels(labels);
    return _parseInt(value);
  }

  int? _intValueRange(List<String> labels, int min, int max) {
    final labelSet = labels.map(_normalize).toSet();
    for (var i = 0; i < _lines.length; i++) {
      final norm = _normalize(_lines[i]);
      if (!labelSet.any((label) => _containsLabel(norm, label))) continue;
      for (final j in <int>[i, i - 1, i + 1, i - 2, i + 2, i - 3, i + 3]) {
        if (j < 0 || j >= _lines.length) continue;
        final value = _parseInt(_lines[j]);
        if (value != null && value >= min && value <= max) {
          _record(labels.first, value.toString(), 0.76, j);
          return value;
        }
      }
    }
    return null;
  }


  int? _signedIntValue(List<String> labels) {
    final value = _valueForLabels(labels);
    return _parseSignedInt(value);
  }

  int? _signedIntValueRange(List<String> labels, int min, int max) {
    final labelSet = labels.map(_normalize).toSet();
    for (var i = 0; i < _lines.length; i++) {
      final norm = _normalize(_lines[i]);
      if (!labelSet.any((label) => _containsLabel(norm, label))) continue;
      for (final j in <int>[i, i - 1, i + 1, i - 2, i + 2, i - 3, i + 3]) {
        if (j < 0 || j >= _lines.length) continue;
        final value = _parseSignedInt(_lines[j]);
        if (value != null && value >= min && value <= max) {
          _record(labels.first, value.toString(), 0.76, j);
          return value;
        }
      }
    }
    return null;
  }

  int _currency(List<String> labels) => _intValue(labels) ?? 0;

  String _sectionAfter(List<String> labels) {
    final normalizedLabels = labels.map(_normalize).toSet();
    for (var i = 0; i < _lines.length; i++) {
      if (!normalizedLabels.any((label) => _normalize(_lines[i]) == label || _normalize(_lines[i]).contains(label))) continue;
      final values = <String>[];
      for (var j = i + 1; j < _lines.length && j < i + 12; j++) {
        final line = _lines[j];
        if (_isLikelySectionHeader(line)) break;
        if (line.isEmpty) break;
        values.add(line);
      }
      return values.join(' ').trim();
    }
    return '';
  }

  List<AttackModel> _extractAttacks() {
    final start = _indexAfterAny([
      'АТАКИ И ЗАКЛИНАНИЯ',
      'ATTACKS AND SPELLCASTING',
      'ATTACKS & SPELLCASTING',
    ]);
    if (start < 0) return const [];

    final attacks = <AttackModel>[];
    final seen = <String>{};
    for (var i = start; i < _lines.length && i < start + 150; i++) {
      final line = _lines[i].trim();
      final dice = RegExp(r'\b\d+\s*[кk]\s*\d+\b', caseSensitive: false).firstMatch(line);
      if (dice == null) continue;
      final bonusMatch = RegExp(r'[+-]\s*\d{1,2}').allMatches(line).toList();
      if (bonusMatch.isEmpty) continue;
      final beforeDice = line.substring(0, dice.start).trim();
      if (beforeDice.isEmpty || beforeDice.length > 80) continue;
      var cleanedName = beforeDice.replaceAll(RegExp(r'[|•·]+'), ' ').trim();
      cleanedName = cleanedName.replaceFirst(RegExp(r'\s*[+-]\s*\d{1,2}\s*$'), '').trim();
      cleanedName = cleanedName.replaceFirst(RegExp(r'^\+?\d+\s+'), '').trim();
      if (cleanedName.isEmpty || _looksLikeUiLabel(cleanedName)) continue;

      final attackBonus = bonusMatch.first.group(0)!.replaceAll(' ', '');
      final damage = line.substring(dice.start).trim();
      final key = _normalize('$cleanedName|$attackBonus|$damage');
      if (!seen.add(key)) continue;

      attacks.add(AttackModel(
        characterId: 0,
        name: cleanedName,
        attackBonus: attackBonus,
        damage: damage,
        sortOrder: attacks.length,
      ));
      _record('attack.${attacks.length - 1}', cleanedName, 0.70, i);
      if (attacks.length >= 6) break;
    }
    return attacks;
  }

  List<SpellModel> _extractSpells() {
    var start = _indexAfterExactAny(['ЗАКЛИНАНИЯ', 'SPELLS']);
    if (start < 0) {
      start = _indexAfterAny([
        'ИЗВЕСТНЫЕ ЗАКЛИНАНИЯ',
        'KNOWN SPELLS',
        'НАЗВАНИЕ ЗАКЛИНАНИЯ',
        'SPELL NAME',
      ]);
    }
    if (start < 0) return const [];

    var level = 0;
    final spells = <SpellModel>[];
    final seen = <String>{};
    var sawFirstSlotMarker = false;

    for (var i = start; i < _lines.length && i < start + 140; i++) {
      final line = _lines[i].trim();
      final norm = _normalize(line);
      if (i > start + 3 && _isLikelySectionHeader(line)) break;
      if (_looksLikeUiLabel(line)) continue;
      if (_looksLikeSpellNoise(norm)) continue;

      // OCR on the spell page often preserves the slot counters as isolated
      // lines such as `4 0`, `3 0`, `1 0`. Each such marker starts the next
      // spell level. This is text-order inference only; no PDF coordinates are
      // consulted.
      final slotMatch = RegExp(r'^\d{1,2}\s+0$').firstMatch(norm);
      if (slotMatch != null) {
        level = (level + 1).clamp(1, 9).toInt();
        sawFirstSlotMarker = true;
        continue;
      }

      if (line.length < 3 || line.length > 90) continue;
      if (_containsTooMuchNarrative(line)) continue;

      var name = line.replaceFirst(RegExp(r'^[-•·*]\s*'), '').trim();
      if (name.contains(' - ')) {
        final suffix = name.substring(name.indexOf(' - ') + 3).trim();
        // Spell-list OCR frequently appends compact casting metadata after
        // the name. Keep the name, not the UI metadata.
        if (RegExp(r'[0-9]|\b(?:ВС|ВТ|Д|Мгн|РАД|М|Км)\b', caseSensitive: false).hasMatch(suffix)) {
          name = name.substring(0, name.indexOf(' - ')).trim();
        }
      }

      final normalized = _normalize(name);
      if (!seen.add(normalized)) continue;
      if (_looksLikeSpellNoise(normalized)) continue;
      if (_isKnownLabel(normalized)) continue;

      // Before the first slot marker the spell page is the cantrip block.
      // Afterwards the counters move us through levels 1..9.
      if (level > 0 || !sawFirstSlotMarker) {
        spells.add(SpellModel(
          characterId: 0,
          name: name,
          level: level,
        ));
        _record('spell', name, 0.65, i);
      }
      if (spells.length >= 100) break;
    }
    return spells;
  }

  int? _parseSpellLevel(String normalizedLine) {
    final patterns = <RegExp>[
      RegExp(r'^(\d+)(?:ST|ND|RD|TH)?\s*LEVEL'),
      RegExp(r'^LEVEL\s*(\d+)'),
      RegExp(r'^(\d+)\s*УРОВЕНЬ'),
      RegExp(r'^УРОВЕНЬ\s*(\d+)'),
      RegExp(r'^ЗАГОВОРЫ'),
      RegExp(r'^CANTRIPS'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalizedLine);
      if (match == null) continue;
      if (normalizedLine.startsWith('ЗАГОВОРЫ') || normalizedLine.startsWith('CANTRIPS')) return 0;
      final parsed = int.tryParse(match.group(1) ?? '');
      if (parsed != null && parsed >= 0 && parsed <= 9) return parsed;
    }
    return null;
  }

  int _indexAfterExactAny(List<String> labels) {
    final normalized = labels.map(_normalize).toSet();
    for (var i = 0; i < _lines.length; i++) {
      if (normalized.contains(_normalize(_lines[i]))) return i + 1;
    }
    return -1;
  }

  int _indexAfterAny(List<String> labels) {
    final normalized = labels.map(_normalize).toList();
    for (var i = 0; i < _lines.length; i++) {
      final line = _normalize(_lines[i]);
      if (normalized.any((label) => line == label || line.contains(label))) return i + 1;
    }
    return -1;
  }

  bool _containsLabel(String line, String label) {
    if (line == label) return true;
    if (label.length <= 3) {
      return RegExp(r'(^|[^A-ZА-Я0-9])' + RegExp.escape(label) + r'([^A-ZА-Я0-9]|$)').hasMatch(line);
    }
    return line.startsWith(label) || line.contains(' $label ') || line.endsWith(' $label');
  }

  String _valueAfterLabel(String original, String normalizedLabel) {
    final originalNormalized = _normalize(original);
    final index = originalNormalized.indexOf(normalizedLabel);
    if (index < 0) return '';
    final raw = originalNormalized.substring(index + normalizedLabel.length).trim();
    if (raw.isEmpty || raw == ':' || raw == '-') return '';
    return original.substring(_findOriginalSuffixStart(original, normalizedLabel)).trim().replaceFirst(RegExp(r'^[:\-]+\s*'), '').trim();
  }

  int _findOriginalSuffixStart(String original, String normalizedLabel) {
    final upper = original.toUpperCase().replaceAll('Ё', 'Е');
    final match = RegExp(RegExp.escape(normalizedLabel).replaceAll(' ', r'\\s+')).firstMatch(upper);
    return match?.end ?? original.length;
  }

  List<int> _numberCandidates(String text) {
    return RegExp(r'(?<!\d)\d{1,2}(?!\d)')
        .allMatches(text)
        .map((m) => int.tryParse(m.group(0)!) ?? -1)
        .where((v) => v >= 0)
        .toList();
  }

  bool _isLikelySectionHeader(String line) {
    final normalized = _normalize(line);
    const headers = [
      'ИМЯ ПЕРСОНАЖА', 'РАСА', 'КЛАСС И УРОВЕНЬ', 'ПРЕДЫСТОРИЯ',
      'МИРОВОЗЗРЕНИЕ', 'ОПЫТ', 'АТАКИ И ЗАКЛИНАНИЯ', 'ЗАКЛИНАНИЯ',
      'УМЕНИЯ И СПОСОБНОСТИ', 'ПРОЧИЕ ВЛАДЕНИЯ И ЯЗЫКИ', 'СНАРЯЖЕНИЕ',
      'ЧЕРТЫ ХАРАКТЕРА', 'ИДЕАЛЫ', 'ПРИВЯЗАННОСТИ', 'СЛАБОСТИ',
      'PERSONALITY TRAITS', 'IDEALS', 'BONDS', 'FLAWS', 'EQUIPMENT',
      'ATTACKS AND SPELLCASTING', 'SPELLS',
    ];
    return headers.any((header) => normalized == header);
  }

  bool _isKnownLabel(String value) {
    final normalized = _normalize(value);
    const known = {
      'ИМЯ ПЕРСОНАЖА', 'РАСА', 'КЛАСС И УРОВЕНЬ', 'ПРЕДЫСТОРИЯ',
      'МИРОВОЗЗРЕНИЕ', 'ОПЫТ', 'ИМЯ ИГРОКА', 'CHARACTER NAME', 'RACE',
      'CLASS AND LEVEL', 'BACKGROUND', 'ALIGNMENT', 'PLAYER NAME',
      'STRENGTH', 'DEXTERITY', 'CONSTITUTION', 'INTELLIGENCE', 'WISDOM', 'CHARISMA',
      'СИЛА', 'ЛОВКОСТЬ', 'ТЕЛОСЛОЖЕНИЕ', 'ИНТЕЛЛЕКТ', 'МУДРОСТЬ', 'ХАРИЗМА',
      'КД', 'AC', 'ИНИЦИАТИВА', 'INITIATIVE', 'СКОРОСТЬ', 'SPEED',
      'ТЕКУЩИЕ ХИТЫ', 'CURRENT HIT POINTS', 'CURRENT HP',
      'МАКСИМУМ ХИТОВ', 'MAXIMUM HIT POINTS', 'MAX HP',
      'ВРЕМЕННЫЕ ХИТЫ', 'TEMPORARY HIT POINTS', 'TEMP HP',
    };
    return known.contains(normalized);
  }

  bool _looksLikeUiLabel(String value) {
    final normalized = _normalize(value);
    if (normalized.length < 2) return true;
    if (normalized.length > 70) return false;
    const labels = [
      'КД', 'AC', 'ИНИЦИАТИВА', 'INITIATIVE', 'СКОРОСТЬ', 'SPEED',
      'ТЕКУЩИЕ ХИТЫ', 'CURRENT HIT POINTS', 'МАКСИМУМ ХИТОВ',
      'MAXIMUM HIT POINTS', 'ВРЕМЕННЫЕ ХИТЫ', 'TEMPORARY HIT POINTS',
      'СИЛА', 'ЛОВКОСТЬ', 'ТЕЛОСЛОЖЕНИЕ', 'ИНТЕЛЛЕКТ', 'МУДРОСТЬ', 'ХАРИЗМА',
      'STRENGTH', 'DEXTERITY', 'CONSTITUTION', 'INTELLIGENCE', 'WISDOM', 'CHARISMA',
    ];
    return labels.contains(normalized);
  }

  bool _looksLikeCantripEntry(String line) {
    final normalized = _normalize(line);
    if (normalized.length < 4) return false;
    return !normalized.contains('УРОВЕН') && !_isLikelySectionHeader(line);
  }

  bool _looksLikeSpellNoise(String normalized) {
    const noise = {
      'НАЗВАНИЕ ЗАКЛИНАНИЯ', 'SPELL NAME', 'УРОВЕНЬ', 'LEVEL',
      'ИТОГО ЯЧЕЕК', 'ЯЧЕЕК ИЗРАСХОДОВАНО', 'TOTAL SLOTS', 'SLOTS USED',
    };
    return noise.contains(normalized);
  }

  bool _containsTooMuchNarrative(String line) {
    return line.length > 95 && !RegExp(r'\d').hasMatch(line);
  }

  (String, int) _parseClassLevel(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) return ('', 1);
    final match = RegExp(r'^(.*?)(?:\s+)(\d+)$').firstMatch(cleaned);
    if (match == null) return (cleaned, 1);
    return (match.group(1)!.trim(), int.tryParse(match.group(2)!) ?? 1);
  }

  int? _parseInt(String raw) {
    if (raw.trim().isEmpty) return null;
    final match = RegExp(r'[-+]?\d+').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  int? _parseSignedInt(String raw) {
    if (raw.trim().isEmpty) return null;
    final match = RegExp(r'[+-]?\s*\d+').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(0)!.replaceAll(' ', ''));
  }

  String _normalizeAbility(String raw) {
    switch (_normalize(raw)) {
      case 'CHA':
      case 'ХАР':
      case 'ХАРИЗМА':
      case 'XAR':
        return 'cha';
      case 'STR':
      case 'СИЛ':
      case 'СИЛА':
        return 'str';
      case 'DEX':
      case 'ЛОВ':
      case 'ЛОВКОСТЬ':
        return 'dex';
      case 'CON':
      case 'ТЕЛ':
      case 'ТЕЛОСЛОЖЕНИЕ':
        return 'con';
      case 'INT':
      case 'ИНТ':
      case 'ИНТЕЛЛЕКТ':
        return 'int';
      case 'WIS':
      case 'МДР':
      case 'МУДРОСТЬ':
        return 'wis';
      default:
        return raw.trim();
    }
  }

  String _normalize(String value) => value
      .toUpperCase()
      .replaceAll('Ё', 'Е')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  void _record(String key, String value, double confidence, int lineIndex) {
    _evidence.add(PdfImportField(
      key: key,
      value: value,
      confidence: confidence,
      source: 'ocr',
      page: 0,
    ));
  }
}

class PdfImportException implements Exception {
  final String message;
  const PdfImportException(this.message);

  @override
  String toString() => message;
}

class _RawPdfField {
  final String name;
  final String mappingName;
  final String value;
  final _RawPdfFieldKind kind;
  final int page;

  const _RawPdfField({
    required this.name,
    required this.mappingName,
    required this.value,
    required this.kind,
    required this.page,
  });
}

enum _RawPdfFieldKind { text, checkbox }
