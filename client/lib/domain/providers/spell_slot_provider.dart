import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/spell_slot_model.dart';
import '../../data/repositories/spell_slot_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class SpellSlotProvider extends ChangeNotifier {
  final SpellSlotRepository _repository = SpellSlotRepository();
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  SpellSlotProvider({SyncService? syncService}) : _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  int? _characterId;
  Map<int, SpellSlotModel> _slotsByLevel = {};
  bool _loading = false;

  bool get loading => _loading;

  SpellSlotModel slotFor(int level) =>
      _slotsByLevel[level] ?? SpellSlotModel(characterId: _characterId ?? 0, level: level);

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
    final updated = current.copyWith(
      syncId: current.syncId.isEmpty ? SyncIds.newId() : current.syncId,
      total: total < 0 ? 0 : total,
    );
    await _repository.upsert(updated);
    _slotsByLevel[level] = updated;
    notifyListeners();
    await _syncService?.publishEntity('spell_slot', updated.toMap());
  }

  Future<void> adjustUsed(int level, int delta) async {
    final characterId = _characterId;
    if (characterId == null) return;
    final current = slotFor(level);
    final int newUsed = (current.used + delta).clamp(0, current.total).toInt();
    final updated = current.copyWith(
      syncId: current.syncId.isEmpty ? SyncIds.newId() : current.syncId,
      used: newUsed,
    );
    await _repository.upsert(updated);
    _slotsByLevel[level] = updated;
    notifyListeners();
    await _syncService?.publishEntity('spell_slot', updated.toMap());
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'spell_slot') {
      final id = _characterId;
      if (id != null) await loadForCharacter(id);
    }
  }

  void clear() {
    _characterId = null;
    _slotsByLevel = {};
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
