import 'package:flutter/foundation.dart';

import '../../data/models/library_item_model.dart';
import '../../data/repositories/library_repository.dart';

/// Provider для Local Content Library (см. docs/D&D Hub.md п.20-22).
///
/// В отличие от остальных provider'ов, не привязан к конкретному
/// персонажу — данные общие для всего приложения (см. п.34: библиотека
/// отделена от персонажей).
class LibraryProvider extends ChangeNotifier {
  final LibraryRepository _repository = LibraryRepository();

  List<LibraryItemModel> _items = [];
  bool _loading = false;
  LibraryItemType? _typeFilter;
  String _query = '';
  String _sort = 'nameAsc';
  final Set<int> _selectedIds = <int>{};
  bool _selectionMode = false;

  List<LibraryItemModel> get items => List.unmodifiable(_items);
  bool get loading => _loading;
  LibraryItemType? get typeFilter => _typeFilter;
  String get query => _query;
  String get sort => _sort;
  Set<int> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get selectionMode => _selectionMode;

  /// Группировка по типу для отображения разделами (Spells/Items/...).
  Map<LibraryItemType, List<LibraryItemModel>> get itemsByType {
    final map = <LibraryItemType, List<LibraryItemModel>>{};
    for (final item in _items) {
      map.putIfAbsent(item.type, () => []).add(item);
    }
    return map;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _items = await _repository.search(_query, type: _typeFilter);
    _sortItems();
    _loading = false;
    notifyListeners();
  }

  Future<void> setTypeFilter(LibraryItemType? type) async {
    _typeFilter = type;
    if (type == LibraryItemType.spell) {
      // Для заклинаний по умолчанию используем естественный порядок D&D:
      // заговоры (0 уровень) -> 1 -> ... -> 9 уровень.
      _sort = 'levelAsc';
    } else if (!_sortIsValidForType(type)) {
      _sort = 'nameAsc';
    }
    await load();
  }

  Future<void> setSort(String sort) async {
    _sort = sort;
    _sortItems();
    notifyListeners();
  }

  void enterSelectionMode() {
    _selectionMode = true;
    notifyListeners();
  }

  void toggleSelection(int id) {
    _selectionMode = true;
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    notifyListeners();
  }

  void selectAllVisible() {
    _selectedIds.addAll(_items.where((item) => item.id != null).map((item) => item.id!));
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _selectionMode = false;
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    await _repository.deleteMany(ids);
    _items.removeWhere((item) => item.id != null && ids.contains(item.id));
    _selectedIds.clear();
    _selectionMode = false;
    notifyListeners();
  }

  bool _sortIsValidForType(LibraryItemType? type) {
    if (_sort == 'levelAsc' || _sort == 'levelDesc') return type == LibraryItemType.spell;
    if (_sort == 'rarity') return type == LibraryItemType.item;
    return true;
  }

  Future<void> setQuery(String query) async {
    _query = query;
    await load();
  }

  Future<LibraryItemModel> addItem(LibraryItemModel item) async {
    final id = await _repository.create(item);
    final created = item.copyWith(id: id);
    _items.add(created);
    notifyListeners();
    return created;
  }

  Future<void> updateItem(LibraryItemModel item) async {
    final updated = item.copyWith(updatedAt: DateTime.now());
    await _repository.update(updated);
    final index = _items.indexWhere((i) => i.id == updated.id);
    if (index != -1) {
      _items[index] = updated;
      notifyListeners();
    }
  }

  void _sortItems() {
    int compareText(Object? a, Object? b) =>
        (a?.toString() ?? '').toLowerCase().compareTo((b?.toString() ?? '').toLowerCase());

    int levelOf(LibraryItemModel item) =>
        (item.data['level'] is num) ? (item.data['level'] as num).toInt() : 999;

    int rarityRank(LibraryItemModel item) {
      const ranks = {
        'обычный': 0, 'необычный': 1, 'редкий': 2,
        'очень редкий': 3, 'легендарный': 4, 'артефакт': 5,
      };
      final rarity = (item.data['rarity'] ?? '').toString().toLowerCase().trim();
      return ranks[rarity] ?? 99;
    }

    _items.sort((a, b) {
      switch (_sort) {
        case 'nameDesc':
          return compareText(b.name, a.name);
        case 'newest':
          return b.createdAt.compareTo(a.createdAt);
        case 'oldest':
          return a.createdAt.compareTo(b.createdAt);
        case 'type':
          final byType = a.type.index.compareTo(b.type.index);
          return byType != 0 ? byType : compareText(a.name, b.name);
        case 'levelAsc':
          final byLevel = levelOf(a).compareTo(levelOf(b));
          return byLevel != 0 ? byLevel : compareText(a.name, b.name);
        case 'levelDesc':
          final byLevel = levelOf(b).compareTo(levelOf(a));
          return byLevel != 0 ? byLevel : compareText(a.name, b.name);
        case 'rarity':
          final byRarity = rarityRank(a).compareTo(rarityRank(b));
          return byRarity != 0 ? byRarity : compareText(a.name, b.name);
        case 'category':
          // Для заклинаний в роли категории используется школа,
          // для остальных объектов — их обычная категория.
          final categoryA = a.type == LibraryItemType.spell
              ? (a.data['school'] ?? a.data['category'])
              : a.data['category'];
          final categoryB = b.type == LibraryItemType.spell
              ? (b.data['school'] ?? b.data['category'])
              : b.data['category'];
          final byCategory = compareText(categoryA, categoryB);
          if (byCategory != 0) return byCategory;

          // Внутри одной категории заклинания всё равно идут
          // от заговора к 9 уровню.
          if (a.type == LibraryItemType.spell && b.type == LibraryItemType.spell) {
            final byLevel = levelOf(a).compareTo(levelOf(b));
            if (byLevel != 0) return byLevel;
          }
          return compareText(a.name, b.name);
        case 'nameAsc':
        default:
          return compareText(a.name, b.name);
      }
    });
  }

  Future<void> deleteItem(int id) async {
    await _repository.delete(id);
    _items.removeWhere((i) => i.id == id);
    notifyListeners();
  }
}
