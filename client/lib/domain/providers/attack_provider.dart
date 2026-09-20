import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/attack_model.dart';
import '../../data/repositories/attack_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class AttackProvider extends ChangeNotifier {
  final AttackRepository _repository = AttackRepository();
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  AttackProvider({SyncService? syncService}) : _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  int? _characterId;
  List<AttackModel> _attacks = [];
  bool _loading = false;

  List<AttackModel> get attacks => List.unmodifiable(_attacks);
  bool get loading => _loading;

  Future<void> loadForCharacter(int characterId) async {
    _characterId = characterId;
    _loading = true;
    notifyListeners();
    _attacks = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addAttack(AttackModel attack) async {
    final normalized = attack.copyWith(syncId: attack.syncId.isEmpty ? SyncIds.newId() : attack.syncId);
    final id = await _repository.create(normalized);
    final created = normalized.copyWith(id: id);
    _attacks.add(created);
    notifyListeners();
    await _syncService?.publishEntity('attack', created.toMap());
  }

  Future<void> updateAttack(AttackModel attack) async {
    await _repository.update(attack);
    final index = _attacks.indexWhere((a) => a.id == attack.id);
    if (index != -1) _attacks[index] = attack;
    notifyListeners();
    await _syncService?.publishEntity('attack', attack.toMap());
  }

  Future<void> deleteAttack(int id) async {
    final removed = _attacks.cast<AttackModel?>().firstWhere((a) => a?.id == id, orElse: () => null);
    await _repository.delete(id);
    _attacks.removeWhere((a) => a.id == id);
    notifyListeners();
    if (removed != null) await _syncService?.publishDelete('attack', removed.syncId);
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'attack') {
      final id = _characterId;
      if (id != null) await loadForCharacter(id);
    }
  }

  void clear() {
    _characterId = null;
    _attacks = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
