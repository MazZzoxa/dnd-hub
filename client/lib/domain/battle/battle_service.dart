import '../../data/models/session_model.dart';
import '../../data/models/battle_model.dart';

class BattleService {
  const BattleService();

  void validateStart({
    required SessionModel session,
    required BattleModel? activeBattle,
  }) {
    if (session.status != SessionStatus.active) {
      throw StateError('Бой можно начать только в активной сессии.');
    }
    if (activeBattle != null) {
      throw StateError('В этой сессии уже есть активный бой.');
    }
  }

  void validateActiveBattle(BattleModel? battle) {
    if (battle == null || battle.status != BattleStatus.active) {
      throw StateError('Активного боя нет.');
    }
  }
}
