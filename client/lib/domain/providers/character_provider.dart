import 'package:flutter/foundation.dart';

import '../../data/models/character_model.dart';
import '../../data/repositories/character_repository.dart';
import '../xp/xp_service.dart';
import '../xp/xp_level_table.dart';
import '../xp/xp_level_table.dart';

/// Хранит список персонажей и текущего выбранного персонажа.
/// Инкапсулирует все быстрые изменения (HP / XP / Gold / владения /
/// вдохновение / спасброски смерти), которые должны выполняться максимально
/// быстро во время сессии (см. п.15 ТЗ).
class CharacterProvider extends ChangeNotifier {
  final CharacterRepository _repository = CharacterRepository();
  final XpService _xpService = XpService();

  List<CharacterModel> _characters = [];
  CharacterModel? _selected;
  bool _loading = false;

  List<CharacterModel> get characters => List.unmodifiable(_characters);
  CharacterModel? get selected => _selected;
  bool get loading => _loading;

  Future<void> loadCharacters() async {
    _loading = true;
    notifyListeners();
    _characters = await _repository.getAll();
    _loading = false;
    notifyListeners();
  }

  void selectCharacter(CharacterModel character) {
    _selected = character;
    notifyListeners();
  }

  void clearSelection() {
    _selected = null;
    notifyListeners();
  }

  Future<CharacterModel> createCharacter(CharacterModel character) async {
    final normalized = character.copyWith(level: XpLevelTable.levelForXp(character.xp));
    final id = await _repository.create(normalized);
    final created = normalized.copyWith(id: id);
    _characters.add(created);
    _selected = created;
    notifyListeners();
    return created;
  }

  Future<void> updateCharacter(CharacterModel character) async {
    final normalized = character.copyWith(level: XpLevelTable.levelForXp(character.xp));
    await _repository.update(normalized);
    _replaceInList(normalized);
    if (_selected?.id == normalized.id) {
      _selected = normalized;
    }
    notifyListeners();
  }

  Future<void> deleteCharacter(int id) async {
    await _repository.delete(id);
    _characters.removeWhere((c) => c.id == id);
    if (_selected?.id == id) {
      _selected = null;
    }
    notifyListeners();
  }

  void _replaceInList(CharacterModel character) {
    final index = _characters.indexWhere((c) => c.id == character.id);
    if (index != -1) {
      _characters[index] = character;
    }
  }

  // --- Быстрые изменения ---

  Future<void> adjustHp(int delta) async {
    final c = _selected;
    if (c == null) return;
    final newHp = (c.hp + delta).clamp(0, c.maxHp + c.temporaryHp);
    await updateCharacter(c.copyWith(hp: newHp));
  }

  Future<void> setTemporaryHp(int value) async {
    final c = _selected;
    if (c == null) return;
    await updateCharacter(c.copyWith(temporaryHp: value < 0 ? 0 : value));
  }

  Future<void> adjustXp(int delta, {String reason = ''}) async {
    final c = _selected;
    if (c == null || delta == 0) return;
    final int newXp = (c.xp + delta).clamp(0, 1 << 30).toInt();
    if (newXp == c.xp) return;
    final transaction = await _xpService.change(c, delta, reason: reason);
    final updated = c.copyWith(xp: transaction.xpAfter, level: transaction.levelAfter);
    _replaceInList(updated);
    _selected = updated;
    notifyListeners();
  }

  Future<void> adjustGold(int delta) async {
    final c = _selected;
    if (c == null) return;
    final newGold = (c.gold + delta).clamp(0, 1 << 30);
    await updateCharacter(c.copyWith(gold: newGold));
  }

  // --- Владения (спасброски / навыки) ---

  Future<void> toggleSavingThrowProficiency(String abilityKey) async {
    final c = _selected;
    if (c == null) return;
    final updated = Set<String>.from(c.savingThrowProficiencies);
    if (!updated.remove(abilityKey)) {
      updated.add(abilityKey);
    }
    await updateCharacter(c.copyWith(savingThrowProficiencies: updated));
  }

  Future<void> toggleSkillProficiency(String skillKey) async {
    final c = _selected;
    if (c == null) return;
    final updated = Set<String>.from(c.skillProficiencies);
    if (!updated.remove(skillKey)) {
      updated.add(skillKey);
    }
    await updateCharacter(c.copyWith(skillProficiencies: updated));
  }

  // --- Вдохновение / кость хитов / спасброски смерти ---

  Future<void> toggleInspiration() async {
    final c = _selected;
    if (c == null) return;
    await updateCharacter(c.copyWith(inspiration: !c.inspiration));
  }

  Future<void> setDeathSaveSuccesses(int value) async {
    final c = _selected;
    if (c == null) return;
    await updateCharacter(c.copyWith(deathSaveSuccesses: value.clamp(0, 3)));
  }

  Future<void> setDeathSaveFailures(int value) async {
    final c = _selected;
    if (c == null) return;
    await updateCharacter(c.copyWith(deathSaveFailures: value.clamp(0, 3)));
  }

  Future<void> resetDeathSaves() async {
    final c = _selected;
    if (c == null) return;
    await updateCharacter(c.copyWith(deathSaveSuccesses: 0, deathSaveFailures: 0));
  }
}
