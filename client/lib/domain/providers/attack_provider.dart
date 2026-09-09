import 'package:flutter/foundation.dart';

import '../../data/models/attack_model.dart';
import '../../data/repositories/attack_repository.dart';

class AttackProvider extends ChangeNotifier {
  final AttackRepository _repository = AttackRepository();

  List<AttackModel> _attacks = [];
  bool _loading = false;

  List<AttackModel> get attacks => List.unmodifiable(_attacks);
  bool get loading => _loading;

  Future<void> loadForCharacter(int characterId) async {
    _loading = true;
    notifyListeners();
    _attacks = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addAttack(AttackModel attack) async {
    final id = await _repository.create(attack);
    _attacks.add(attack.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateAttack(AttackModel attack) async {
    await _repository.update(attack);
    final index = _attacks.indexWhere((a) => a.id == attack.id);
    if (index != -1) {
      _attacks[index] = attack;
    }
    notifyListeners();
  }

  Future<void> deleteAttack(int id) async {
    await _repository.delete(id);
    _attacks.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  void clear() {
    _attacks = [];
    notifyListeners();
  }
}
