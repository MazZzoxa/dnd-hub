import '../../data/models/character_model.dart';

class BattleRules {
  static CharacterModel applyDamage(CharacterModel character, int amount) {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Урон не может быть отрицательным.',
      );
    }

    final absorbed = amount.clamp(0, character.temporaryHp).toInt();
    final remaining = amount - absorbed;

    final nextHp = (character.hp - remaining).clamp(0, character.maxHp).toInt();
    return character.copyWith(
      hp: nextHp,
      temporaryHp: character.temporaryHp - absorbed,
      lifeState: nextHp == 0 && character.lifeState == CharacterLifeState.normal
          ? CharacterLifeState.downed
          : character.lifeState,
    );
  }

  static CharacterModel heal(CharacterModel character, int amount) {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Лечение не может быть отрицательным.',
      );
    }

    return character.copyWith(
      hp: (character.hp + amount).clamp(0, character.maxHp).toInt(),
    );
  }

  static CharacterModel setTemporaryHp(CharacterModel character, int amount) {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Временные хиты не могут быть отрицательными.',
      );
    }

    return character.copyWith(temporaryHp: amount);
  }
}
