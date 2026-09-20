import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/xp_transaction_model.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_service.dart';
import '../xp/xp_service.dart';

class XpProvider extends ChangeNotifier {
  final XpService _service;
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  XpProvider({XpService? service, SyncService? syncService})
      : _service = service ?? XpService(),
        _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  List<XpTransactionModel> _history = [];
  bool _loading = false;
  int? _characterId;
  bool _historyLoaded = false;

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

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'xp_transaction' || entity == 'character') {
      await refresh();
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
