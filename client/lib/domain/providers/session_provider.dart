import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/session_model.dart';
import '../../data/repositories/session_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class SessionProvider extends ChangeNotifier {
  final SessionRepository _repository;
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  SessionProvider({SessionRepository? repository, SyncService? syncService})
      : _repository = repository ?? SessionRepository(),
        _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  List<SessionModel> _sessions = [];
  SessionModel? _active;
  bool _loading = false;
  int? _campaignId;

  List<SessionModel> get sessions => List.unmodifiable(_sessions);
  SessionModel? get active => _active;
  bool get loading => _loading;

  Future<void> load(int campaignId) async {
    _campaignId = campaignId;
    _loading = true;
    notifyListeners();
    _sessions = await _repository.getForCampaign(campaignId);
    _active = null;
    for (final session in _sessions) {
      if (session.status == SessionStatus.active) {
        _active = session;
        break;
      }
    }
    _loading = false;
    notifyListeners();
  }

  Future<SessionModel> startSession({
    required int campaignId,
    required String title,
  }) async {
    final now = DateTime.now();
    final active = await _repository.getActive(campaignId);
    if (active != null) {
      throw StateError('В этой кампании уже есть активная сессия. Сначала завершите её.');
    }
    final session = SessionModel(
      syncId: SyncIds.newId(),
      campaignId: campaignId,
      title: title.trim().isEmpty ? 'Новая сессия' : title.trim(),
      status: SessionStatus.active,
      createdAt: now,
      startedAt: now,
      updatedAt: now,
    );
    final id = await _repository.create(session);
    await load(campaignId);
    final created = _sessions.firstWhere((item) => item.id == id);
    await _syncService?.publishEntity('session', created.toMap());
    return created;
  }

  Future<void> updateActive({String? title, String? notes}) async {
    final session = _active;
    if (session == null) return;
    final updated = session.copyWith(
      title: title ?? session.title,
      notes: notes ?? session.notes,
      updatedAt: DateTime.now(),
    );
    await _repository.update(updated);
    _replace(updated);
    _active = updated;
    notifyListeners();
    await _syncService?.publishEntity('session', updated.toMap());
  }

  Future<void> completeActive() async {
    final session = _active;
    if (session == null) return;
    final now = DateTime.now();
    final updated = session.copyWith(
      status: SessionStatus.completed,
      endedAt: now,
      updatedAt: now,
    );
    await _repository.update(updated);
    _replace(updated);
    _active = null;
    notifyListeners();
    await _syncService?.publishEntity('session', updated.toMap());
  }

  Future<void> deleteSession(SessionModel session) async {
    if (session.id == null) return;
    await _repository.delete(session.id!);
    _sessions.removeWhere((item) => item.id == session.id);
    if (_active?.id == session.id) _active = null;
    notifyListeners();
    await _syncService?.publishDelete('session', session.syncId);
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'session') {
      final id = _campaignId;
      if (id != null) await load(id);
    }
  }

  void _replace(SessionModel session) {
    final index = _sessions.indexWhere((item) => item.id == session.id);
    if (index == -1) {
      _sessions.insert(0, session);
    } else {
      _sessions[index] = session;
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
