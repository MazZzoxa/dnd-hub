import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/library_item_model.dart';
import '../../data/repositories/library_repository.dart';
import 'library_type_labels.dart';

/// Открывает bottom sheet с поиском по Local Content Library, отфильтрованным
/// по [type], и возвращает выбранный объект (или null, если отменено).
///
/// Работает напрямую через [LibraryRepository], а не через общий
/// [LibraryProvider] (см. docs/D&D Hub.md п.34) — так открытие пикера с
/// экрана персонажа не перезаписывает фильтр/поиск, выставленные на самом
/// экране библиотеки.
Future<LibraryItemModel?> showLibraryPickerDialog(
  BuildContext context, {
  required LibraryItemType type,
}) {
  return showModalBottomSheet<LibraryItemModel>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _LibraryPickerSheet(type: type),
  );
}

class _LibraryPickerSheet extends StatefulWidget {
  final LibraryItemType type;

  const _LibraryPickerSheet({required this.type});

  @override
  State<_LibraryPickerSheet> createState() => _LibraryPickerSheetState();
}

class _LibraryPickerSheetState extends State<_LibraryPickerSheet> {
  final _repository = LibraryRepository();
  final _searchController = TextEditingController();
  List<LibraryItemModel> _results = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await _repository.search(query, type: widget.type);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LibraryTypeLabels.icon(widget.type), color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Добавить из библиотеки: ${LibraryTypeLabels.plural(widget.type)}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Поиск по названию…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: _search,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Text(
                                'В библиотеке нет подходящих объектов.\nДобавьте их через экран «Библиотека».',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppTheme.textSecondary),
                              ),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final item = _results[index];
                              return Material(
                                color: AppTheme.surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => Navigator.of(context).pop(item),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.name,
                                            style: const TextStyle(fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                        const Icon(Icons.add_circle_outline,
                                            color: AppTheme.primary),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
