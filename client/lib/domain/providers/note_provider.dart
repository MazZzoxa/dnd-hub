import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/note_model.dart';
import '../../data/repositories/note_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class NoteProvider extends ChangeNotifier {
  final NoteRepository _repository = NoteRepository();
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  NoteProvider({SyncService? syncService}) : _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  int? _characterId;
  List<NoteModel> _notes = [];
  bool _loading = false;

  List<NoteModel> get notes => List.unmodifiable(_notes);
  bool get loading => _loading;

  Future<void> loadForCharacter(int characterId) async {
    _characterId = characterId;
    _loading = true;
    notifyListeners();
    _notes = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addNote(NoteModel note) async {
    final normalized = note.copyWith(syncId: note.syncId.isEmpty ? SyncIds.newId() : note.syncId);
    final id = await _repository.create(normalized);
    final created = normalized.copyWith(id: id);
    _notes.insert(0, created);
    notifyListeners();
    await _syncService?.publishEntity('note', created.toMap());
  }

  Future<void> updateNote(NoteModel note) async {
    await _repository.update(note);
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) _notes[index] = note;
    notifyListeners();
    await _syncService?.publishEntity('note', note.toMap());
  }

  Future<void> deleteNote(int id) async {
    final removed = _notes.cast<NoteModel?>().firstWhere((n) => n?.id == id, orElse: () => null);
    await _repository.delete(id);
    _notes.removeWhere((n) => n.id == id);
    notifyListeners();
    if (removed != null) await _syncService?.publishDelete('note', removed.syncId);
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'note') {
      final id = _characterId;
      if (id != null) await loadForCharacter(id);
    }
  }

  void clear() {
    _characterId = null;
    _notes = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
