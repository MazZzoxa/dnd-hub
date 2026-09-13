/// Справочные данные D&D 5e, используемые для спасбросков, навыков и
/// пассивных характеристик. Ключи характеристик всегда: str, dex, con,
/// int, wis, cha — используются как для спасбросков, так и как ability
/// заклинателя.

class AbilityInfo {
  final String key;
  final String shortLabel;
  final String fullLabel;
  const AbilityInfo(this.key, this.shortLabel, this.fullLabel);
}

const List<AbilityInfo> kAbilities = [
  AbilityInfo('str', 'СИЛ', 'Сила'),
  AbilityInfo('dex', 'ЛОВ', 'Ловкость'),
  AbilityInfo('con', 'ТЕЛ', 'Телосложение'),
  AbilityInfo('int', 'ИНТ', 'Интеллект'),
  AbilityInfo('wis', 'МДР', 'Мудрость'),
  AbilityInfo('cha', 'ХАР', 'Харизма'),
];

class SkillInfo {
  final String key;
  final String label;
  final String ability; // str/dex/con/int/wis/cha
  const SkillInfo(this.key, this.label, this.ability);
}

/// Список из 18 навыков, как на стандартном листе персонажа.
const List<SkillInfo> kSkills = [
  SkillInfo('acrobatics', 'Акробатика', 'dex'),
  SkillInfo('investigation', 'Анализ', 'int'),
  SkillInfo('athletics', 'Атлетика', 'str'),
  SkillInfo('perception', 'Внимательность', 'wis'),
  SkillInfo('survival', 'Выживание', 'wis'),
  SkillInfo('performance', 'Выступление', 'cha'),
  SkillInfo('intimidation', 'Запугивание', 'cha'),
  SkillInfo('history', 'История', 'int'),
  SkillInfo('sleight_of_hand', 'Ловкость рук', 'dex'),
  SkillInfo('arcana', 'Магия', 'int'),
  SkillInfo('medicine', 'Медицина', 'wis'),
  SkillInfo('deception', 'Обман', 'cha'),
  SkillInfo('nature', 'Природа', 'int'),
  SkillInfo('insight', 'Проницательность', 'wis'),
  SkillInfo('religion', 'Религия', 'int'),
  SkillInfo('stealth', 'Скрытность', 'dex'),
  SkillInfo('persuasion', 'Убеждение', 'cha'),
  SkillInfo('animal_handling', 'Уход за животными', 'wis'),
];

/// Навык, от которого считается пассивная Мудрость (Внимательность).
const String kPerceptionSkillKey = 'perception';
