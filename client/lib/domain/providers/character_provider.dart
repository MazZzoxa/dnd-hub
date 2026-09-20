import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/character_model.dart';
import '../../data/repositories/character_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';
import '../xp/xp_service.dart';
import '../xp/xp_level_table.dart';

/// Хранит список персонажей и текущего выбранного персонажа.
/// Инкапсулирует все быстрые изменения (HP / XP / Gold / владения /
/// вдохновение / спасброски смерти), которые должны выполняться максимально
/// быстро во время сессии (см. п.15 ТЗ).
class CharacterProvider extends ChangeNotifier {
  final CharacterRepository _repository;
  final XpService _xpService = XpService();
  final SyncService? _syncService;
  bool _applyingRemote = false;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  CharacterProvider({CharacterRepository? repository, SyncService? syncService})
      : _repository = repository ?? CharacterRepository(),
        _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onNetworkEvent);
  }

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
    final normalized = character.copyWith(
      level: XpLevelTable.levelForXp(character.xp),
      syncId: character.syncId.isEmpty ? SyncIds.newId() : character.syncId,
    );
    final id = await _repository.create(normalized);
    final created = normalized.copyWith(id: id);
    _characters.add(created);
    _selected = created;
    notifyListeners();
    await _syncService?.publishCharacter(created);
    return created;
  }

  Future<void> updateCharacter(CharacterModel character) async {
    final normalized = character.copyWith(
      level: XpLevelTable.levelForXp(character.xp),
      syncId: character.syncId.isEmpty ? SyncIds.newId() : character.syncId,
    );
    await _repository.update(normalized);
    _replaceInList(normalized);
    if (_selected?.id == normalized.id) {
      _selected = normalized;
    }
    notifyListeners();
    if (!_applyingRemote) {
      await _syncService?.publishCharacter(normalized);
    }
  }

  Future<void> deleteCharacter(int id) async {
    final index = _characters.indexWhere((c) => c.id == id);
    final removed = index == -1 ? null : _characters[index];
    await _repository.delete(id);
    _characters.removeWhere((c) => c.id == id);
    if (_selected?.id == id) _selected = null;
    notifyListeners();
    if (!_applyingRemote && removed != null) {
      await _syncService?.publishDelete('character', removed.syncId);
    }
  }

  void _replaceInList(CharacterModel character) {
    final index = _characters.indexWhere((c) => c.id == character.id);
    if (index != -1) {
      _characters[index] = character;
    }
  }

  Future<void> _onNetworkEvent(NetworkMessage event) async {
    final eventName = event.payload['event']?.toString();
    final entity = event.payload['entity']?.toString();
    if (eventName == 'state.snapshot') {
      final selectedSyncId = _selected?.syncId;
      await loadCharacters();
      if (selectedSyncId != null && selectedSyncId.isNotEmpty) {
        for (final character in _characters) {
          if (character.syncId == selectedSyncId) {
            _selected = character;
            break;
          }
        }
      }
      notifyListeners();
      return;
    }
    if (entity != 'character') return;
    final selectedSyncId = _selected?.syncId;
    await loadCharacters();
    if (eventName == 'state.delete') {
      if (selectedSyncId != null &&
          selectedSyncId == event.payload['sync_id']?.toString()) {
        _selected = null;
      }
    } else if (selectedSyncId != null && selectedSyncId.isNotEmpty) {
      for (final character in _characters) {
        if (character.syncId == selectedSyncId) {
          _selected = character;
          break;
        }
      }
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  // --- Быстрые изменения ---

  Future<void> adjustHp(int delta) async {
    final c = _selected;
    if (c == null) return;
    final int newHp = (c.hp + delta).clamp(0, c.maxHp + c.temporaryHp).toInt();
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
    if (!_applyingRemote) {
      await _syncService?.publishCharacter(updated);
      await _syncService?.publishEntity('xp_transaction', transaction.toMap());
    }
  }

  Future<void> adjustGold(int delta) async {
    final c = _selected;
    if (c == null) return;
    final int newGold = (c.gold + delta).clamp(0, 1 << 30).toInt();
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
    await updateCharacter(c.copyWith(deathSaveSuccesses: value.clamp(0, 3).toInt()));
  }

  Future<void> setDeathSaveFailures(int value) async {
    final c = _selected;
    if (c == null) return;
    await updateCharacter(c.copyWith(deathSaveFailures: value.clamp(0, 3).toInt()));
  }

  Future<void> resetDeathSaves() async {
    final c = _selected;
    if (c == null) return;
    await updateCharacter(c.copyWith(deathSaveSuccesses: 0, deathSaveFailures: 0));
  }
}
