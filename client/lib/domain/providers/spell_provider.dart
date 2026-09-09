import 'package:flutter/foundation.dart';

import '../../data/models/spell_model.dart';
import '../../data/repositories/spell_repository.dart';

class SpellProvider extends ChangeNotifier {
  final SpellRepository _repository = SpellRepository();

  List<SpellModel> _spells = [];
  bool _loading = false;

  List<SpellModel> get spells => List.unmodifiable(_spells);
  bool get loading => _loading;

  Map<int, List<SpellModel>> get spellsByLevel {
    final map = <int, List<SpellModel>>{};
    for (final spell in _spells) {
      map.putIfAbsent(spell.level, () => []).add(spell);
    }
    return map;
  }

  Future<void> loadForCharacter(int characterId) async {
    _loading = true;
    notifyListeners();
    _spells = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addSpell(SpellModel spell) async {
    final id = await _repository.create(spell);
    _spells.add(spell.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateSpell(SpellModel spell) async {
    await _repository.update(spell);
    final index = _spells.indexWhere((s) => s.id == spell.id);
    if (index != -1) {
      _spells[index] = spell;
    }
    notifyListeners();
  }

  Future<void> deleteSpell(int id) async {
    await _repository.delete(id);
    _spells.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  void clear() {
    _spells = [];
    notifyListeners();
  }
}
