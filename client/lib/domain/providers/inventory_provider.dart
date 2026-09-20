import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/item_model.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_ids.dart';
import '../../network/services/sync_service.dart';

class InventoryProvider extends ChangeNotifier {
  final InventoryRepository _repository = InventoryRepository();
  final SyncService? _syncService;
  StreamSubscription<NetworkMessage>? _syncSubscription;

  InventoryProvider({SyncService? syncService}) : _syncService = syncService {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  int? _characterId;
  List<ItemModel> _items = [];
  bool _loading = false;

  List<ItemModel> get items => List.unmodifiable(_items);
  bool get loading => _loading;

  Map<String, List<ItemModel>> get itemsByCategory {
    final map = <String, List<ItemModel>>{};
    for (final item in _items) map.putIfAbsent(item.category, () => []).add(item);
    return map;
  }

  Future<void> loadForCharacter(int characterId) async {
    _characterId = characterId;
    _loading = true;
    notifyListeners();
    _items = await _repository.getForCharacter(characterId);
    _loading = false;
    notifyListeners();
  }

  Future<void> addItem(ItemModel item) async {
    final normalized = item.copyWith(syncId: item.syncId.isEmpty ? SyncIds.newId() : item.syncId);
    final id = await _repository.create(normalized);
    final created = normalized.copyWith(id: id);
    _items.add(created);
    notifyListeners();
    await _syncService?.publishEntity('item', created.toMap());
  }

  Future<void> updateItem(ItemModel item) async {
    await _repository.update(item);
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) _items[index] = item;
    notifyListeners();
    await _syncService?.publishEntity('item', item.toMap());
  }

  Future<void> deleteItem(int id) async {
    final removed = _items.cast<ItemModel?>().firstWhere((i) => i?.id == id, orElse: () => null);
    await _repository.delete(id);
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
    if (removed != null) await _syncService?.publishDelete('item', removed.syncId);
  }

  Future<void> adjustQuantity(ItemModel item, int delta) async {
    final newQuantity = item.quantity + delta;
    if (newQuantity <= 0) {
      await deleteItem(item.id!);
      return;
    }
    await updateItem(item.copyWith(quantity: newQuantity));
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'state.snapshot' || entity == 'item') {
      final id = _characterId;
      if (id != null) await loadForCharacter(id);
    }
  }

  void clear() {
    _characterId = null;
    _items = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
