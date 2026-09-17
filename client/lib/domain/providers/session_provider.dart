import 'package:flutter/foundation.dart';

import '../../data/models/session_model.dart';
import '../../data/repositories/session_repository.dart';

class SessionProvider extends ChangeNotifier {
  final SessionRepository _repository;

  SessionProvider({SessionRepository? repository})
      : _repository = repository ?? SessionRepository();

  List<SessionModel> _sessions = [];
  SessionModel? _active;
  bool _loading = false;

  List<SessionModel> get sessions => List.unmodifiable(_sessions);
  SessionModel? get active => _active;
  bool get loading => _loading;

  Future<void> load(int campaignId) async {
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
      campaignId: campaignId,
      title: title.trim().isEmpty ? 'Новая сессия' : title.trim(),
      status: SessionStatus.active,
      createdAt: now,
      startedAt: now,
      updatedAt: now,
    );
    final id = await _repository.create(session);
    await load(campaignId);
    return _sessions.firstWhere((item) => item.id == id);
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
  }

  Future<void> deleteSession(SessionModel session) async {
    if (session.id == null) return;
    await _repository.delete(session.id!);
    _sessions.removeWhere((item) => item.id == session.id);
    if (_active?.id == session.id) _active = null;
    notifyListeners();
  }

  void _replace(SessionModel session) {
    final index = _sessions.indexWhere((item) => item.id == session.id);
    if (index == -1) {
      _sessions.insert(0, session);
    } else {
      _sessions[index] = session;
    }
  }
}
