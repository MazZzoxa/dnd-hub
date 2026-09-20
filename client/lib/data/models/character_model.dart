import 'dart:convert';

/// Внутренняя модель персонажа D&D Hub.
/// Не зависит от формата внешнего источника или любого другого внешнего источника —
/// см. принцип №6 в документе проекта (docs/D_D_Hub.md, п.22).
class CharacterModel {
  final int? id;
  final String syncId;

  // Identity
  final String name;
  final String race;
  final String className;
  final String subclass;
  final String background;
  final int level;
  final String alignment; // мировоззрение
  final String playerName;

  // Attributes
  final int strength;
  final int dexterity;
  final int constitution;
  final int intelligence;
  final int wisdom;
  final int charisma;

  // Combat
  final int hp;
  final int maxHp;
  final int temporaryHp;
  final int armorClass;
  final int initiative;
  final int speed;
  final int proficiencyBonus;
  final bool inspiration;
  final String hitDice; // напр. "20к10"
  final int deathSaveSuccesses; // 0..3
  final int deathSaveFailures; // 0..3

  // Proficiencies (хранятся как множества ключей: str/dex/.../навыки)
  final Set<String> savingThrowProficiencies;
  final Set<String> skillProficiencies;

  // Progression
  final int xp;

  // Currency
  final int copper;
  final int silver;
  final int electrum;
  final int gold;
  final int platinum;

  // Spellcasting
  final String spellcastingClass; // напр. "Хар" — короткая метка на листе
  final String spellcastingAbility; // str/dex/con/int/wis/cha или ''

  // Roleplay / Background
  final String personalityTraits;
  final String ideals;
  final String bonds;
  final String flaws;
  final String proficienciesLanguages; // владения и языки текстом
  final String age;
  final String height;
  final String weight;
  final String eyes;
  final String skin;
  final String hair;
  final String backstory;
  final String alliesOrganizations;
  final String treasure;
  final String bioImageBase64;

  const CharacterModel({
    this.id,
    this.syncId = '',
    required this.name,
    this.race = '',
    this.className = '',
    this.subclass = '',
    this.background = '',
    this.level = 1,
    this.alignment = '',
    this.playerName = '',
    this.strength = 10,
    this.dexterity = 10,
    this.constitution = 10,
    this.intelligence = 10,
    this.wisdom = 10,
    this.charisma = 10,
    this.hp = 10,
    this.maxHp = 10,
    this.temporaryHp = 0,
    this.armorClass = 10,
    this.initiative = 0,
    this.speed = 30,
    this.proficiencyBonus = 2,
    this.inspiration = false,
    this.hitDice = '',
    this.deathSaveSuccesses = 0,
    this.deathSaveFailures = 0,
    this.savingThrowProficiencies = const {},
    this.skillProficiencies = const {},
    this.xp = 0,
    this.copper = 0,
    this.silver = 0,
    this.electrum = 0,
    this.gold = 0,
    this.platinum = 0,
    this.spellcastingClass = '',
    this.spellcastingAbility = '',
    this.personalityTraits = '',
    this.ideals = '',
    this.bonds = '',
    this.flaws = '',
    this.proficienciesLanguages = '',
    this.age = '',
    this.height = '',
    this.weight = '',
    this.eyes = '',
    this.skin = '',
    this.hair = '',
    this.backstory = '',
    this.alliesOrganizations = '',
    this.treasure = '',
    this.bioImageBase64 = '',
  });

  /// Модификатор характеристики по правилам D&D: floor((score - 10) / 2)
  static int modifier(int score) => ((score - 10) / 2).floor();

  int get strengthMod => modifier(strength);
  int get dexterityMod => modifier(dexterity);
  int get constitutionMod => modifier(constitution);
  int get intelligenceMod => modifier(intelligence);
  int get wisdomMod => modifier(wisdom);
  int get charismaMod => modifier(charisma);

  int abilityScore(String key) {
    switch (key) {
      case 'str':
        return strength;
      case 'dex':
        return dexterity;
      case 'con':
        return constitution;
      case 'int':
        return intelligence;
      case 'wis':
        return wisdom;
      case 'cha':
        return charisma;
      default:
        return 10;
    }
  }

  int abilityMod(String key) => modifier(abilityScore(key));

  /// Модификатор спасброска: модификатор характеристики + бонус мастерства,
  /// если персонаж владеет этим спасброском.
  int savingThrowMod(String abilityKey) {
    final base = abilityMod(abilityKey);
    return savingThrowProficiencies.contains(abilityKey) ? base + proficiencyBonus : base;
  }

  /// Модификатор навыка по его ключу (см. dnd_data.dart) с учётом владения.
  int skillMod(String skillKey, String abilityKey) {
    final base = abilityMod(abilityKey);
    return skillProficiencies.contains(skillKey) ? base + proficiencyBonus : base;
  }

  /// Пассивная Мудрость (Внимательность) = 10 + модификатор навыка Внимательность.
  int passivePerception(int perceptionSkillMod) => 10 + perceptionSkillMod;

  /// Сложность спасения заклинания = 8 + бонус мастерства + модификатор ability.
  int get spellSaveDC {
    if (spellcastingAbility.isEmpty) return 0;
    return 8 + proficiencyBonus + abilityMod(spellcastingAbility);
  }

  /// Бонус атаки заклинанием = бонус мастерства + модификатор ability.
  int get spellAttackBonus {
    if (spellcastingAbility.isEmpty) return 0;
    return proficiencyBonus + abilityMod(spellcastingAbility);
  }

  CharacterModel copyWith({
    int? id,
    String? syncId,
    String? name,
    String? race,
    String? className,
    String? subclass,
    String? background,
    int? level,
    String? alignment,
    String? playerName,
    int? strength,
    int? dexterity,
    int? constitution,
    int? intelligence,
    int? wisdom,
    int? charisma,
    int? hp,
    int? maxHp,
    int? temporaryHp,
    int? armorClass,
    int? initiative,
    int? speed,
    int? proficiencyBonus,
    bool? inspiration,
    String? hitDice,
    int? deathSaveSuccesses,
    int? deathSaveFailures,
    Set<String>? savingThrowProficiencies,
    Set<String>? skillProficiencies,
    int? xp,
    int? copper,
    int? silver,
    int? electrum,
    int? gold,
    int? platinum,
    String? spellcastingClass,
    String? spellcastingAbility,
    String? personalityTraits,
    String? ideals,
    String? bonds,
    String? flaws,
    String? proficienciesLanguages,
    String? age,
    String? height,
    String? weight,
    String? eyes,
    String? skin,
    String? hair,
    String? backstory,
    String? alliesOrganizations,
    String? treasure,
    String? bioImageBase64,
  }) {
    return CharacterModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      name: name ?? this.name,
      race: race ?? this.race,
      className: className ?? this.className,
      subclass: subclass ?? this.subclass,
      background: background ?? this.background,
      level: level ?? this.level,
      alignment: alignment ?? this.alignment,
      playerName: playerName ?? this.playerName,
      strength: strength ?? this.strength,
      dexterity: dexterity ?? this.dexterity,
      constitution: constitution ?? this.constitution,
      intelligence: intelligence ?? this.intelligence,
      wisdom: wisdom ?? this.wisdom,
      charisma: charisma ?? this.charisma,
      hp: hp ?? this.hp,
      maxHp: maxHp ?? this.maxHp,
      temporaryHp: temporaryHp ?? this.temporaryHp,
      armorClass: armorClass ?? this.armorClass,
      initiative: initiative ?? this.initiative,
      speed: speed ?? this.speed,
      proficiencyBonus: proficiencyBonus ?? this.proficiencyBonus,
      inspiration: inspiration ?? this.inspiration,
      hitDice: hitDice ?? this.hitDice,
      deathSaveSuccesses: deathSaveSuccesses ?? this.deathSaveSuccesses,
      deathSaveFailures: deathSaveFailures ?? this.deathSaveFailures,
      savingThrowProficiencies: savingThrowProficiencies ?? this.savingThrowProficiencies,
      skillProficiencies: skillProficiencies ?? this.skillProficiencies,
      xp: xp ?? this.xp,
      copper: copper ?? this.copper,
      silver: silver ?? this.silver,
      electrum: electrum ?? this.electrum,
      gold: gold ?? this.gold,
      platinum: platinum ?? this.platinum,
      spellcastingClass: spellcastingClass ?? this.spellcastingClass,
      spellcastingAbility: spellcastingAbility ?? this.spellcastingAbility,
      personalityTraits: personalityTraits ?? this.personalityTraits,
      ideals: ideals ?? this.ideals,
      bonds: bonds ?? this.bonds,
      flaws: flaws ?? this.flaws,
      proficienciesLanguages: proficienciesLanguages ?? this.proficienciesLanguages,
      age: age ?? this.age,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      eyes: eyes ?? this.eyes,
      skin: skin ?? this.skin,
      hair: hair ?? this.hair,
      backstory: backstory ?? this.backstory,
      alliesOrganizations: alliesOrganizations ?? this.alliesOrganizations,
      treasure: treasure ?? this.treasure,
      bioImageBase64: bioImageBase64 ?? this.bioImageBase64,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sync_id': syncId,
      'name': name,
      'race': race,
      'class_name': className,
      'subclass': subclass,
      'background': background,
      'level': level,
      'alignment': alignment,
      'player_name': playerName,
      'strength': strength,
      'dexterity': dexterity,
      'constitution': constitution,
      'intelligence': intelligence,
      'wisdom': wisdom,
      'charisma': charisma,
      'hp': hp,
      'max_hp': maxHp,
      'temporary_hp': temporaryHp,
      'armor_class': armorClass,
      'initiative': initiative,
      'speed': speed,
      'proficiency_bonus': proficiencyBonus,
      'inspiration': inspiration ? 1 : 0,
      'hit_dice': hitDice,
      'death_save_successes': deathSaveSuccesses,
      'death_save_failures': deathSaveFailures,
      'saving_throw_proficiencies': jsonEncode(savingThrowProficiencies.toList()),
      'skill_proficiencies': jsonEncode(skillProficiencies.toList()),
      'xp': xp,
      'copper': copper,
      'silver': silver,
      'electrum': electrum,
      'gold': gold,
      'platinum': platinum,
      'spellcasting_class': spellcastingClass,
      'spellcasting_ability': spellcastingAbility,
      'personality_traits': personalityTraits,
      'ideals': ideals,
      'bonds': bonds,
      'flaws': flaws,
      'proficiencies_languages': proficienciesLanguages,
      'age': age,
      'height': height,
      'weight': weight,
      'eyes': eyes,
      'skin': skin,
      'hair': hair,
      'backstory': backstory,
      'allies_organizations': alliesOrganizations,
      'treasure': treasure,
      'bio_image': bioImageBase64,
    };
  }

  static Set<String> _decodeStringSet(dynamic raw) {
    if (raw == null) return {};
    try {
      final list = jsonDecode(raw as String) as List;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  factory CharacterModel.fromMap(Map<String, dynamic> map) {
    return CharacterModel(
      id: map['id'] as int?,
      syncId: map['sync_id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      race: map['race'] as String? ?? '',
      className: map['class_name'] as String? ?? '',
      subclass: map['subclass'] as String? ?? '',
      background: map['background'] as String? ?? '',
      level: map['level'] as int? ?? 1,
      alignment: map['alignment'] as String? ?? '',
      playerName: map['player_name'] as String? ?? '',
      strength: map['strength'] as int? ?? 10,
      dexterity: map['dexterity'] as int? ?? 10,
      constitution: map['constitution'] as int? ?? 10,
      intelligence: map['intelligence'] as int? ?? 10,
      wisdom: map['wisdom'] as int? ?? 10,
      charisma: map['charisma'] as int? ?? 10,
      hp: map['hp'] as int? ?? 10,
      maxHp: map['max_hp'] as int? ?? 10,
      temporaryHp: map['temporary_hp'] as int? ?? 0,
      armorClass: map['armor_class'] as int? ?? 10,
      initiative: map['initiative'] as int? ?? 0,
      speed: map['speed'] as int? ?? 30,
      proficiencyBonus: map['proficiency_bonus'] as int? ?? 2,
      inspiration: (map['inspiration'] as int? ?? 0) == 1,
      hitDice: map['hit_dice'] as String? ?? '',
      deathSaveSuccesses: map['death_save_successes'] as int? ?? 0,
      deathSaveFailures: map['death_save_failures'] as int? ?? 0,
      savingThrowProficiencies: _decodeStringSet(map['saving_throw_proficiencies']),
      skillProficiencies: _decodeStringSet(map['skill_proficiencies']),
      xp: map['xp'] as int? ?? 0,
      copper: map['copper'] as int? ?? 0,
      silver: map['silver'] as int? ?? 0,
      electrum: map['electrum'] as int? ?? 0,
      gold: map['gold'] as int? ?? 0,
      platinum: map['platinum'] as int? ?? 0,
      spellcastingClass: map['spellcasting_class'] as String? ?? '',
      spellcastingAbility: map['spellcasting_ability'] as String? ?? '',
      personalityTraits: map['personality_traits'] as String? ?? '',
      ideals: map['ideals'] as String? ?? '',
      bonds: map['bonds'] as String? ?? '',
      flaws: map['flaws'] as String? ?? '',
      proficienciesLanguages: map['proficiencies_languages'] as String? ?? '',
      age: map['age'] as String? ?? '',
      height: map['height'] as String? ?? '',
      weight: map['weight'] as String? ?? '',
      eyes: map['eyes'] as String? ?? '',
      skin: map['skin'] as String? ?? '',
      hair: map['hair'] as String? ?? '',
      backstory: map['backstory'] as String? ?? '',
      alliesOrganizations: map['allies_organizations'] as String? ?? '',
      treasure: map['treasure'] as String? ?? '',
      bioImageBase64: map['bio_image'] as String? ?? '',
    );
  }
}
