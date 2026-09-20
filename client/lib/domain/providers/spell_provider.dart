import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/spell_model.dart';
import '../../data/repositories/spell_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class SpellProvider extends ChangeNotifier {
  final SpellRepository _repository = SpellRepository();
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  SpellProvider({SyncService? syncService}) : _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  int? _characterId;
  List<SpellModel> _spells = [];
  bool _loading = false;

  List<SpellModel> get spells => List.unmodifiable(_spells);
  bool get loading => _loading;

  Map<int, List<SpellModel>> get spellsByLevel {
    final map = <int, List<SpellModel>>{};
    for (final spell in _spells) map.putIfAbsent(spell.level, () => []).add(spell);
    return map;
  }

  Future<void> loadForCharacter(int characterId) async {
    _characterId = characterId;
    _loading = true;
    notifyListeners();
    _spells = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addSpell(SpellModel spell) async {
    final normalized = spell.copyWith(syncId: spell.syncId.isEmpty ? SyncIds.newId() : spell.syncId);
    final id = await _repository.create(normalized);
    final created = normalized.copyWith(id: id);
    _spells.add(created);
    notifyListeners();
    await _syncService?.publishEntity('spell', created.toMap());
  }

  Future<void> updateSpell(SpellModel spell) async {
    await _repository.update(spell);
    final index = _spells.indexWhere((s) => s.id == spell.id);
    if (index != -1) _spells[index] = spell;
    notifyListeners();
    await _syncService?.publishEntity('spell', spell.toMap());
  }

  Future<void> deleteSpell(int id) async {
    final removed = _spells.cast<SpellModel?>().firstWhere((s) => s?.id == id, orElse: () => null);
    await _repository.delete(id);
    _spells.removeWhere((s) => s.id == id);
    notifyListeners();
    if (removed != null) await _syncService?.publishDelete('spell', removed.syncId);
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'spell') {
      final id = _characterId;
      if (id != null) await loadForCharacter(id);
    }
  }

  void clear() {
    _characterId = null;
    _spells = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
