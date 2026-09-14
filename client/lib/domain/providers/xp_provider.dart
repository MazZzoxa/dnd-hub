import 'package:flutter/foundation.dart';

import '../../data/models/xp_transaction_model.dart';
import '../xp/xp_service.dart';

class XpProvider extends ChangeNotifier {
  final XpService _service;
  List<XpTransactionModel> _history = [];
  bool _loading = false;
  int? _characterId;
  bool _historyLoaded = false;

  XpProvider({XpService? service}) : _service = service ?? XpService();

  List<XpTransactionModel> get history => List.unmodifiable(_history);
  bool get loading => _loading;

  Future<void> loadHistory(int characterId) async {
    if (_characterId == characterId && !_loading && _historyLoaded) return;
    _characterId = characterId;
    _historyLoaded = false;
    _loading = true;
    notifyListeners();
    _history = await _service.history(characterId);
    _historyLoaded = true;
    _loading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    final id = _characterId;
    if (id == null) return;
    _history = await _service.history(id);
    _historyLoaded = true;
    notifyListeners();
  }
}
