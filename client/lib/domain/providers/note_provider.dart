import 'package:flutter/foundation.dart';

import '../../data/models/note_model.dart';
import '../../data/repositories/note_repository.dart';

class NoteProvider extends ChangeNotifier {
  final NoteRepository _repository = NoteRepository();

  List<NoteModel> _notes = [];
  bool _loading = false;

  List<NoteModel> get notes => List.unmodifiable(_notes);
  bool get loading => _loading;

  Future<void> loadForCharacter(int characterId) async {
    _loading = true;
    notifyListeners();
    _notes = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addNote(NoteModel note) async {
    final id = await _repository.create(note);
    _notes.insert(0, note.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateNote(NoteModel note) async {
    await _repository.update(note);
    final index = _notes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      _notes[index] = note;
    }
    notifyListeners();
  }

  Future<void> deleteNote(int id) async {
    await _repository.delete(id);
    _notes.removeWhere((n) => n.id == id);
    notifyListeners();
  }

  void clear() {
    _notes = [];
    notifyListeners();
  }
}
