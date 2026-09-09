import 'package:flutter/foundation.dart';

import '../../data/models/spell_slot_model.dart';
import '../../data/repositories/spell_slot_repository.dart';

/// Хранит ячейки заклинаний для всех 9 уровней текущего персонажа.
/// Уровни без явно заданных ячеек считаются total=0/used=0.
class SpellSlotProvider extends ChangeNotifier {
  final SpellSlotRepository _repository = SpellSlotRepository();

  int? _characterId;
  Map<int, SpellSlotModel> _slotsByLevel = {};
  bool _loading = false;

  bool get loading => _loading;

  SpellSlotModel slotFor(int level) =>
      _slotsByLevel[level] ??
      SpellSlotModel(characterId: _characterId ?? 0, level: level);

  Future<void> loadForCharacter(int characterId) async {
    _characterId = characterId;
    _loading = true;
    notifyListeners();
    final slots = await _repository.getForCharacter(characterId);
    _slotsByLevel = {for (final s in slots) s.level: s};
    _loading = false;
    notifyListeners();
  }

  Future<void> setTotal(int level, int total) async {
    final characterId = _characterId;
    if (characterId == null) return;
    final current = slotFor(level);
    final updated = current.copyWith(total: total < 0 ? 0 : total);
    await _repository.upsert(updated);
    _slotsByLevel[level] = updated;
    notifyListeners();
  }

  Future<void> adjustUsed(int level, int delta) async {
    final characterId = _characterId;
    if (characterId == null) return;
    final current = slotFor(level);
    final newUsed = (current.used + delta).clamp(0, current.total);
    final updated = current.copyWith(used: newUsed);
    await _repository.upsert(updated);
    _slotsByLevel[level] = updated;
    notifyListeners();
  }

  void clear() {
    _characterId = null;
    _slotsByLevel = {};
    notifyListeners();
  }
}
