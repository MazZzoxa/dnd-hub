import 'package:flutter/foundation.dart';

import '../../data/models/ability_model.dart';
import '../../data/repositories/ability_repository.dart';

class AbilityProvider extends ChangeNotifier {
  final AbilityRepository _repository = AbilityRepository();

  List<AbilityModel> _abilities = [];
  bool _loading = false;

  List<AbilityModel> get abilities => List.unmodifiable(_abilities);
  bool get loading => _loading;

  Future<void> loadForCharacter(int characterId) async {
    _loading = true;
    notifyListeners();
    _abilities = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addAbility(AbilityModel ability) async {
    final abilityWithOrder = ability.copyWith(sortOrder: _abilities.length);
    final id = await _repository.create(abilityWithOrder);
    _abilities.add(abilityWithOrder.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateAbility(AbilityModel ability) async {
    await _repository.update(ability);
    final index = _abilities.indexWhere((a) => a.id == ability.id);
    if (index != -1) {
      _abilities[index] = ability;
    }
    notifyListeners();
  }

  Future<void> deleteAbility(int id) async {
    await _repository.delete(id);
    _abilities.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  Future<void> reorderAbilities(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _abilities.removeAt(oldIndex);
    _abilities.insert(newIndex, item);
    final reordered = [
      for (var i = 0; i < _abilities.length; i++)
        _abilities[i].copyWith(sortOrder: i),
    ];
    _abilities = reordered;
    await _repository.reorder(_abilities);
    notifyListeners();
  }

  void clear() {

    _abilities = [];
    notifyListeners();
  }
}
