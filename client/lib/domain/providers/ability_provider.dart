import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/ability_model.dart';
import '../../data/repositories/ability_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class AbilityProvider extends ChangeNotifier {
  final AbilityRepository _repository = AbilityRepository();
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  AbilityProvider({SyncService? syncService}) : _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  int? _characterId;
  List<AbilityModel> _abilities = [];
  bool _loading = false;

  List<AbilityModel> get abilities => List.unmodifiable(_abilities);
  bool get loading => _loading;

  Future<void> loadForCharacter(int characterId) async {
    _characterId = characterId;
    _loading = true;
    notifyListeners();
    _abilities = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addAbility(AbilityModel ability) async {
    final normalized = ability.copyWith(
      sortOrder: _abilities.length,
      syncId: ability.syncId.isEmpty ? SyncIds.newId() : ability.syncId,
    );
    final id = await _repository.create(normalized);
    final created = normalized.copyWith(id: id);
    _abilities.add(created);
    notifyListeners();
    await _syncService?.publishEntity('ability', created.toMap());
  }

  Future<void> updateAbility(AbilityModel ability) async {
    await _repository.update(ability);
    final index = _abilities.indexWhere((a) => a.id == ability.id);
    if (index != -1) _abilities[index] = ability;
    notifyListeners();
    await _syncService?.publishEntity('ability', ability.toMap());
  }

  Future<void> deleteAbility(int id) async {
    final index = _abilities.indexWhere((a) => a.id == id);
    final removed = index == -1 ? null : _abilities[index];
    await _repository.delete(id);
    _abilities.removeWhere((a) => a.id == id);
    notifyListeners();
    if (removed != null) await _syncService?.publishDelete('ability', removed.syncId);
  }

  Future<void> reorderAbilities(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final item = _abilities.removeAt(oldIndex);
    _abilities.insert(newIndex, item);
    _abilities = [
      for (var i = 0; i < _abilities.length; i++)
        _abilities[i].copyWith(sortOrder: i),
    ];
    await _repository.reorder(_abilities);
    notifyListeners();
    for (final ability in _abilities) {
      await _syncService?.publishEntity('ability', ability.toMap());
    }
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'ability') {
      final id = _characterId;
      if (id != null) await loadForCharacter(id);
    }
  }

  void clear() {
    _characterId = null;
    _abilities = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
