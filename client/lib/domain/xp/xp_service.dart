import '../../data/models/character_model.dart';
import '../../data/models/xp_transaction_model.dart';
import '../../data/repositories/xp_repository.dart';
import 'xp_level_table.dart';
import 'xp_progress.dart';

class XpService {
  final XpRepository _transactions;

  XpService({XpRepository? transactions}) : _transactions = transactions ?? XpRepository();

  XpProgress progress(CharacterModel character) {
    final level = XpLevelTable.levelForXp(character.xp);
    final current = XpLevelTable.xpForLevel(level);
    final next = XpLevelTable.nextLevelXp(level);
    final double ratio = next == null || next <= current
        ? 1.0
        : ((character.xp - current) / (next - current)).clamp(0.0, 1.0).toDouble();
    return XpProgress(
      currentXp: character.xp,
      level: level,
      currentLevelXp: current,
      nextLevelXp: next,
      progress: ratio,
    );
  }

  Future<XpTransactionModel> change(
    CharacterModel character,
    int delta, {
    String reason = '',
  }) async {
    final id = character.id;
    if (id == null) throw StateError('Персонаж должен иметь id.');
    if (delta == 0) throw ArgumentError.value(delta, 'delta', 'Изменение XP не может быть 0.');
    final int newXp = (character.xp + delta).clamp(0, 1 << 30).toInt();
    final newLevel = XpLevelTable.levelForXp(newXp);
    final result = await _transactions.changeXp(
      characterId: id,
      delta: newXp - character.xp,
      newXp: newXp,
      newLevel: newLevel,
      oldXp: character.xp,
      oldLevel: character.level,
      reason: reason,
    );
    return result;
  }

  Future<List<XpTransactionModel>> history(int characterId) => _transactions.getHistory(characterId);
}
