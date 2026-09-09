import 'package:flutter/foundation.dart';

import '../../data/models/item_model.dart';
import '../../data/repositories/inventory_repository.dart';

class InventoryProvider extends ChangeNotifier {
  final InventoryRepository _repository = InventoryRepository();

  int? _characterId;
  List<ItemModel> _items = [];
  bool _loading = false;

  List<ItemModel> get items => List.unmodifiable(_items);
  bool get loading => _loading;

  /// Группировка по категориям для отображения (см. п.16 ТЗ).
  Map<String, List<ItemModel>> get itemsByCategory {
    final map = <String, List<ItemModel>>{};
    for (final item in _items) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
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
    final id = await _repository.create(item);
    _items.add(item.copyWith(id: id));
    notifyListeners();
  }

  Future<void> updateItem(ItemModel item) async {
    await _repository.update(item);
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _items[index] = item;
    }
    notifyListeners();
  }

  Future<void> deleteItem(int id) async {
    await _repository.delete(id);
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  /// Быстрое изменение количества (см. п.16 ТЗ: [-] 3 [+]).
  /// Если количество достигает 0, предмет удаляется.
  Future<void> adjustQuantity(ItemModel item, int delta) async {
    final newQuantity = item.quantity + delta;
    if (newQuantity <= 0) {
      await deleteItem(item.id!);
      return;
    }
    await updateItem(item.copyWith(quantity: newQuantity));
  }

  void clear() {
    _characterId = null;
    _items = [];
    notifyListeners();
  }
}
