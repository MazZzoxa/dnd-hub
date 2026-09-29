import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/session_event_model.dart';
import '../../data/models/session_model.dart';
import '../../data/models/session_history_entry_model.dart';
import '../../data/models/session_loot_model.dart';
import '../../data/models/session_note_model.dart';
import '../../data/models/session_reward_model.dart';
import '../../data/repositories/session_workspace_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class SessionWorkspaceProvider extends ChangeNotifier {
  final SessionWorkspaceRepository _repository;
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _subscription;

  SessionWorkspaceProvider({
    SessionWorkspaceRepository? repository,
    SyncService? syncService,
  })  : _repository = repository ?? SessionWorkspaceRepository(),
        _syncService = syncService {
    _subscription = _syncService?.events.listen(_onSyncEvent);
  }

  int? _sessionId;
  String _sessionSyncId = '';
  List<SessionNoteModel> _notes = [];
  List<SessionEventModel> _events = [];
  List<SessionRewardModel> _rewards = [];
  List<SessionLootModel> _loot = [];
  List<SessionHistoryEntryModel> _history = [];
  int _levelUpCount = 0;
  bool _loading = false;

  List<SessionNoteModel> get notes => List.unmodifiable(_notes);
  List<SessionEventModel> get events => List.unmodifiable(_events);
  List<SessionRewardModel> get rewards => List.unmodifiable(_rewards);
  List<SessionLootModel> get loot => List.unmodifiable(_loot);
  List<SessionHistoryEntryModel> get history => List.unmodifiable(_history);
  int get levelUpCount => _levelUpCount;
  int get battleCount => _history.where((entry) => entry.kind == 'battle').length;
  bool get loading => _loading;
  String get sessionSyncId => _sessionSyncId;
  String get actorId => _syncService?.clientId ?? 'local';
  bool get connected => _syncService?.connected == true;
  bool get isGm => _syncService == null || !connected || _syncService!.role == 'gm';

  Future<void> load(SessionModel session) => loadById(session.id, session.syncId);

  Future<void> loadById(int? sessionId, String sessionSyncId) async {
    if (sessionId == null || sessionSyncId.trim().isEmpty) {
      clear();
      return;
    }
    _sessionId = sessionId;
    _sessionSyncId = sessionSyncId.trim();
    _loading = true;
    notifyListeners();
    await _reload();
    _loading = false;
    notifyListeners();
  }

  Future<void> _reload() async {
    final id = _sessionId;
    if (id == null) return;
    _notes = await _repository.getNotes(id);
    _events = await _repository.getEvents(id);
    _rewards = await _repository.getRewards(id);
    _loot = await _repository.getLoot(id);
    _history = await _repository.getHistory(id);
    _levelUpCount = await _repository.getLevelUpCount(id);
  }

  Future<SessionNoteModel> addNote({required String title, required String content}) async {
    _requireGm();
    final sessionId = _requireSession();
    final now = DateTime.now();
    final note = SessionNoteModel(
      syncId: SyncIds.newId(),
      sessionId: sessionId,
      title: title.trim().isEmpty ? 'Заметка' : title.trim(),
      content: content.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final id = await _repository.createNote(note);
    final created = note.copyWith(id: id);
    final event = await _createLocalEvent(
      type: 'note_created',
      title: created.title,
      description: created.content,
      metadata: {'note_sync_id': created.syncId},
    );
    await _publish('session_note', created.toMap());
    await _publish('session_event', event.toMap());
    await _reloadAndNotify();
    return created;
  }

  Future<void> updateNote(SessionNoteModel note) async {
    _requireGm();
    final updated = note.copyWith(
      title: note.title.trim().isEmpty ? 'Заметка' : note.title.trim(),
      content: note.content.trim(),
      updatedAt: DateTime.now(),
    );
    await _repository.updateNote(updated);
    await _publish('session_note', updated.toMap());
    await _reloadAndNotify();
  }

  Future<void> deleteNote(SessionNoteModel note) async {
    _requireGm();
    await _repository.deleteNote(note);
    await _syncService?.publishDelete('session_note', note.syncId);
    await _reloadAndNotify();
  }

  Future<SessionEventModel> addEvent({
    required String title,
    String description = '',
    String type = 'custom',
  }) async {
    _requireGm();
    final sessionId = _requireSession();
    final event = SessionEventModel(
      syncId: SyncIds.newId(),
      sessionId: sessionId,
      type: type.trim().isEmpty ? 'custom' : type.trim(),
      title: title.trim().isEmpty ? 'Игровое событие' : title.trim(),
      description: description.trim(),
      createdAt: DateTime.now(),
      createdBy: actorId,
    );
    final id = await _repository.createEvent(event);
    final created = event.copyWith(id: id);
    await _publish('session_event', created.toMap());
    await _reloadAndNotify();
    return created;
  }

  Future<SessionLootModel> addLoot({
    required String name,
    String description = '',
    int quantity = 1,
    String source = '',
  }) async {
    _requireGm();
    final sessionId = _requireSession();
    final now = DateTime.now();
    final loot = SessionLootModel(
      syncId: SyncIds.newId(),
      sessionId: sessionId,
      name: name.trim().isEmpty ? 'Новая добыча' : name.trim(),
      description: description.trim(),
      quantity: quantity.clamp(1, 1 << 20).toInt(),
      source: source.trim(),
      createdAt: now,
      updatedAt: now,
    );
    final id = await _repository.createLoot(loot);
    final created = loot.copyWith(id: id);
    final event = await _createLocalEvent(
      type: 'loot_added',
      title: '${created.name} ×${created.quantity}',
      description: created.source.isEmpty ? '' : 'Источник: ${created.source}',
      metadata: {'loot_sync_id': created.syncId, 'quantity': created.quantity},
    );
    await _publish('session_loot', created.toMap());
    await _publish('session_event', event.toMap());
    await _reloadAndNotify();
    return created;
  }

  Future<void> updateLoot(SessionLootModel loot) async {
    _requireGm();
    if (loot.status != 'available') throw StateError('Распределённую добычу нельзя редактировать.');
    final updated = loot.copyWith(
      name: loot.name.trim().isEmpty ? 'Новая добыча' : loot.name.trim(),
      description: loot.description.trim(),
      quantity: loot.quantity.clamp(1, 1 << 20).toInt(),
      source: loot.source.trim(),
      updatedAt: DateTime.now(),
    );
    await _repository.updateLoot(updated);
    await _publish('session_loot', updated.toMap());
    await _reloadAndNotify();
  }

  Future<void> deleteLoot(SessionLootModel loot) async {
    _requireGm();
    if (loot.status != 'available') throw StateError('Распределённую добычу нельзя удалить.');
    await _repository.deleteLoot(loot);
    await _syncService?.publishDelete('session_loot', loot.syncId);
    await _reloadAndNotify();
  }

  Future<void> grantXp({
    required String characterSyncId,
    required int amount,
    String reason = '',
  }) async {
    _requireGm();
    final sessionId = _requireSession();
    if (amount <= 0) throw ArgumentError.value(amount, 'amount', 'XP должен быть положительным.');
    if (connected) {
      await _syncService!.grantSessionXp(
        sessionSyncId: _sessionSyncId,
        characterSyncId: characterSyncId,
        amount: amount,
        reason: reason.trim(),
      );
      return;
    }
    await _repository.grantXpLocally(
      sessionId: sessionId,
      characterSyncId: characterSyncId,
      amount: amount,
      reason: reason.trim(),
      createdBy: actorId,
    );
    await _reloadAndNotify();
  }

  Future<void> claimLoot({
    required String lootSyncId,
    required String characterSyncId,
  }) async {
    _requireGm();
    if (connected) {
      await _syncService!.claimSessionLoot(
        lootSyncId: lootSyncId,
        characterSyncId: characterSyncId,
      );
      return;
    }
    await _repository.claimLootLocally(
      lootSyncId: lootSyncId,
      characterSyncId: characterSyncId,
      createdBy: actorId,
    );
    await _reloadAndNotify();
  }

  Future<void> clear() async {
    _sessionId = null;
    _sessionSyncId = '';
    _notes = [];
    _events = [];
    _rewards = [];
    _loot = [];
    _history = [];
    _levelUpCount = 0;
    notifyListeners();
  }

  Future<SessionEventModel> _createLocalEvent({
    required String type,
    required String title,
    required String description,
    Map<String, dynamic> metadata = const {},
  }) async {
    final event = SessionEventModel(
      syncId: SyncIds.newId(),
      sessionId: _requireSession(),
      type: type,
      title: title,
      description: description,
      metadata: metadata,
      createdAt: DateTime.now(),
      createdBy: actorId,
    );
    final id = await _repository.createEvent(event);
    return event.copyWith(id: id);
  }

  Future<void> _publish(String entity, Map<String, dynamic> data) async {
    await _syncService?.publishEntity(entity, data);
  }

  int _requireSession() {
    final id = _sessionId;
    if (id == null || _sessionSyncId.isEmpty) throw StateError('Сессия не выбрана.');
    return id;
  }

  void _requireGm() {
    if (_syncService != null && connected && !isGm) {
      throw StateError('Только ГМ может изменять рабочее пространство сессии.');
    }
  }

  Future<void> _reloadAndNotify() async {
    await _reload();
    notifyListeners();
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString() ?? '';
    final eventName = event.payload['event']?.toString() ?? '';
    final data = event.payload['data'];
    if (eventName == 'state.snapshot') {
      final sessionId = _sessionId;
      if (sessionId != null) {
        await _reloadAndNotify();
      }
      return;
    }
    if (eventName == 'state.delete') {
      final deleted = event.payload['sync_id']?.toString() ?? '';
      if (entity == 'session') {
        if (deleted == _sessionSyncId) await clear();
      } else if ({'session_note', 'session_event', 'session_reward', 'session_loot'}.contains(entity) && _sessionId != null) {
        await _reloadAndNotify();
      }
      return;
    }
    if (data is Map &&
        {'session_note', 'session_event', 'session_reward', 'session_loot'}.contains(entity)) {
      final syncSession = data['session_sync_id']?.toString() ?? '';
      if (syncSession == _sessionSyncId) await _reloadAndNotify();
      return;
    }
    if (entity == 'session' && data is Map && data['sync_id']?.toString() == _sessionSyncId) {
      await _reloadAndNotify();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

