import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/export/export_manager.dart';
import '../widgets/import_file_dialog.dart';
import '../widgets/import_url_dialog.dart';
import '../widgets/export_format_dialog.dart';
import '../../data/models/library_item_model.dart';
import '../../domain/providers/library_provider.dart';
import '../widgets/library_type_labels.dart';

const _itemCategories = ['Weapons', 'Armor', 'Consumables', 'Other'];

const _itemCategoryLabels = <String, String>{
  'Weapons': 'Оружие',
  'Armor': 'Броня',
  'Consumables': 'Расходуемые предметы',
  'Other': 'Прочее',
};

String _itemCategoryLabel(String category) => _itemCategoryLabels[category] ?? category;

const _castingTimes = [
  '1 действие',
  '1 бонусное действие',
  '1 реакция',
  '1 минута',
  '10 минут',
  '1 час',
  'Другое',
];

/// Экран Local Content Library — см. docs/D&D Hub.md п.20-23.
///
/// В отличие от разделов персонажа, не привязан к character_id: библиотека
/// общая для всего приложения, персонаж лишь ссылается на её объекты
/// (см. п.34, поле library_item_id в items/spells/abilities).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LibraryProvider>().load();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportLibrary(BuildContext context) async {
    final format = await showExportFormatDialog(context);
    if (format == null || !context.mounted) return;

    try {
      final fileName = await ExportManager().exportLibrary(format: format);
      if (!context.mounted || fileName == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Экспортировано: $fileName')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Consumer<LibraryProvider>(
          builder: (context, provider, _) => provider.selectionMode
              ? Text('Выбрано: ${provider.selectedIds.length}')
              : const Text('Библиотека'),
        ),
        leading: Consumer<LibraryProvider>(
          builder: (context, provider, _) => provider.selectionMode
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Выйти из выбора',
                  onPressed: provider.clearSelection,
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Назад',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
        ),
        actions: [
          Consumer<LibraryProvider>(
            builder: (context, provider, _) {
              if (provider.selectionMode) {
                final allSelected = provider.items.isNotEmpty &&
                    provider.items.every((item) => item.id != null && provider.selectedIds.contains(item.id));
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(allSelected ? Icons.deselect : Icons.select_all),
                      tooltip: allSelected ? 'Снять выбор' : 'Выбрать всё',
                      onPressed: allSelected ? provider.clearSelection : provider.selectAllVisible,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Удалить выбранное',
                      onPressed: () => _confirmDeleteSelected(context, provider),
                    ),
                  ],
                );
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.checklist_outlined),
                    tooltip: 'Выбрать объекты',
                    onPressed: provider.enterSelectionMode,
                  ),
                  IconButton(
                    icon: const Icon(Icons.link_outlined),
                    tooltip: 'Импортировать по ссылке',
                    onPressed: () async {
                      final result = await showImportUrlDialog(context);
                      if (!mounted || result == null) return;
                      if (result.importedLibraryItemIds.isNotEmpty) {
                        await context.read<LibraryProvider>().load();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: 'Импортировать файл',
                    onPressed: () async {
                      final result = await showImportFileDialog(context);
                      if (!mounted || result == null) return;
                      if (result.importedLibraryItemIds.isNotEmpty) {
                        await context.read<LibraryProvider>().load();
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_upload_outlined),
                    tooltip: 'Экспортировать библиотеку',
                    onPressed: () => _exportLibrary(context),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<LibraryProvider>(
        builder: (context, provider, _) {
          return Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Поиск по названию…',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  provider.setQuery('');
                                },
                              ),
                      ),
                      onChanged: provider.setQuery,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _FilterChip(
                          label: 'Все',
                          selected: provider.typeFilter == null,
                          onTap: () => provider.setTypeFilter(null),
                        ),
                        for (final type in LibraryItemType.values) ...[
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: LibraryTypeLabels.plural(type),
                            selected: provider.typeFilter == type,
                            onTap: () => provider.setTypeFilter(type),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.sort, size: 18, color: AppTheme.textSecondary),
                        const SizedBox(width: 6),
                        const Text('Сортировка', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _sortOptions(provider).containsKey(provider.sort) ? provider.sort : 'nameAsc',
                                isDense: true,
                                items: _sortOptions(provider)
                                    .entries
                                    .map((entry) => DropdownMenuItem<String>(value: entry.key, child: Text(entry.value)))
                                    .toList(),
                                onChanged: (value) {
                                  if (value != null) provider.setSort(value);
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: provider.loading
                        ? const Center(child: CircularProgressIndicator())
                        : provider.items.isEmpty
                            ? _EmptyState(hasFilter: provider.query.isNotEmpty || provider.typeFilter != null)
                            : _LibraryList(provider: provider),
                  ),
                ],
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: FloatingActionButton(
                  onPressed: () => _onCreate(context, provider),
                  child: const Icon(Icons.add),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onCreate(BuildContext context, LibraryProvider provider) async {
    final preselected = provider.typeFilter;
    if (preselected != null) {
      await _showLibraryItemDialog(context, provider: provider, initialType: preselected);
      return;
    }
    final type = await showModalBottomSheet<LibraryItemType>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Что добавить?', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            ),
            for (final t in LibraryItemType.values)
              ListTile(
                leading: Icon(LibraryTypeLabels.icon(t)),
                title: Text(LibraryTypeLabels.singular(t)),
                onTap: () => Navigator.of(context).pop(t),
              ),
          ],
        ),
      ),
    );
    if (type == null || !context.mounted) return;
    await _showLibraryItemDialog(context, provider: provider, initialType: type);
  }
}


Map<String, String> _sortOptions(LibraryProvider provider) {
  final options = <String, String>{
    'nameAsc': 'Название: А → Я',
    'nameDesc': 'Название: Я → А',
    'newest': 'Сначала новые',
    'oldest': 'Сначала старые',
    'type': 'По типу',
  };
  switch (provider.typeFilter) {
    case LibraryItemType.spell:
      options.addAll({
        'levelAsc': 'Уровень: 0 → 9',
        'levelDesc': 'Уровень: 9 → 0',
        'category': 'По категории',
      });
      break;
    case LibraryItemType.item:
      options.addAll({'rarity': 'По редкости', 'category': 'По категории'});
      break;
    case LibraryItemType.ability:
    case LibraryItemType.other:
    case null:
      options.addAll({'category': 'По категории'});
      break;
  }
  return options;
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppTheme.primary.withOpacity(0.25),
      backgroundColor: AppTheme.surface,
      labelStyle: TextStyle(color: selected ? AppTheme.primary : AppTheme.textSecondary),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}

class _LibraryList extends StatelessWidget {
  final LibraryProvider provider;

  const _LibraryList({required this.provider});

  @override
  Widget build(BuildContext context) {
    // При активном фильтре по типу показываем плоский список,
    // при "Все" — секциями по типу (см. п.20 ТЗ: LocalLibrary по разделам).
    if (provider.typeFilter != null) {
      final items = provider.items;
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _LibraryItemCard(
          item: items[index],
          provider: provider,
        ),
      );
    }

    final grouped = provider.itemsByType;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
      children: [
        for (final type in LibraryItemType.values)
          if (grouped[type]?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text(
                      LibraryTypeLabels.plural(type),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  for (final item in grouped[type]!) ...[
                    _LibraryItemCard(item: item, provider: provider),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
      ],
    );
  }
}

class _LibraryItemCard extends StatelessWidget {
  final LibraryItemModel item;
  final LibraryProvider provider;

  const _LibraryItemCard({required this.item, required this.provider});

  String get _summary {
    switch (item.type) {
      case LibraryItemType.item:
        final category = item.data['category'] as String? ?? 'Other';
        final weight = item.data['weight'];
        final weightLabel = (weight is num && weight > 0) ? ' · $weight фунтов' : '';
        return '${_itemCategoryLabel(category)}$weightLabel';
      case LibraryItemType.spell:
        final level = item.data['level'];
        final school = (item.data['school'] as String? ?? '').trim();
        final levelLabel = (level == null || level == 0) ? 'Заговор' : 'Уровень $level';
        return school.isEmpty ? levelLabel : '$levelLabel · $school';
      case LibraryItemType.ability:
        return (item.data['source'] as String? ?? '').trim();
      case LibraryItemType.other:
        final description = (item.data['description'] as String? ?? '').trim();
        return description.length > 70 ? '${description.substring(0, 70)}…' : description;
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final selected = item.id != null && provider.selectedIds.contains(item.id);
    final selectable = provider.selectionMode;
    return Material(
      color: selected ? AppTheme.primary.withOpacity(0.12) : AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: item.id == null ? null : () => provider.toggleSelection(item.id!),
        onTap: () {
          if (selectable && item.id != null) {
            provider.toggleSelection(item.id!);
          } else {
            _showLibraryItemDialog(context, provider: provider, existing: item);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              if (selectable) ...[
                Checkbox(
                  value: selected,
                  onChanged: item.id == null ? null : (_) => provider.toggleSelection(item.id!),
                ),
                const SizedBox(width: 2),
              ],
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primary.withOpacity(0.15),
                child: Icon(LibraryTypeLabels.icon(item.type), color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(summary,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (!selectable) ...[
                Tooltip(
                  message: LibraryTypeLabels.sourceLabel(item.sourceType),
                  child: Icon(LibraryTypeLabels.sourceIcon(item.sourceType),
                      size: 18, color: AppTheme.textSecondary),
                ),
                IconButton(
                  icon: const Icon(Icons.file_upload_outlined, color: AppTheme.textSecondary),
                  tooltip: 'Экспортировать',
                  onPressed: () => _exportItem(context, item),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppTheme.textSecondary),
                  onPressed: () => _confirmDelete(context, provider, item),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportItem(BuildContext context, LibraryItemModel item) async {
    final format = await showExportFormatDialog(context);
    if (format == null || !context.mounted) return;

    try {
      final fileName = await ExportManager().exportLibraryItem(item, format: format);
      if (!context.mounted || fileName == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Экспортировано: $fileName')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось экспортировать: $error')),
      );
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, LibraryProvider provider, LibraryItemModel item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить объект?'),
        content: Text(
          '«${item.name}» будет удалён из библиотеки. Копии, уже добавленные персонажам, не пострадают.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && item.id != null) {
      await provider.deleteItem(item.id!);
    }
  }
}


Future<void> _confirmDeleteSelected(BuildContext context, LibraryProvider provider) async {
  final count = provider.selectedIds.length;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Удалить выбранные?'),
      content: Text('Будет удалено объектов: $count.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Удалить', style: TextStyle(color: AppTheme.danger)),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    await provider.deleteSelected();
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasFilter;

  const _EmptyState({required this.hasFilter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_stories_outlined, size: 56, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'Ничего не найдено' : 'Библиотека пока пуста',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Попробуйте изменить поиск или фильтр'
                  : 'Добавьте предметы, заклинания и способности, чтобы переиспользовать их для разных персонажей',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Диалог создания/редактирования объекта библиотеки.
///
/// Набор полей зависит от [LibraryItemType] — по образцу
/// _showItemDialog/_showSpellDialog в разделах персонажа (inventory_section
/// / spells_section), но с полем "Ссылка на источник" (п.29 ТЗ) и
/// переключением набора полей при выборе типа во время создания.
Future<void> _showLibraryItemDialog(
  BuildContext context, {
  required LibraryProvider provider,
  LibraryItemModel? existing,
  LibraryItemType? initialType,
}) async {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final sourceUrlController = TextEditingController(text: existing?.sourceUrl ?? '');
  var type = existing?.type ?? initialType ?? LibraryItemType.item;

  final data = existing?.data ?? const <String, dynamic>{};

  // Предмет
  var itemCategory = data['category'] as String? ?? _itemCategories.first;
  final itemWeightController =
      TextEditingController(text: '${(data['weight'] as num?) ?? 0}');

  // Заклинание
  final spellLevelController = TextEditingController(text: '${(data['level'] as num?) ?? 0}');
  final spellSchoolController = TextEditingController(text: data['school'] as String? ?? '');
  final spellRangeController = TextEditingController(text: data['range'] as String? ?? '');
  final spellComponentsController =
      TextEditingController(text: data['components'] as String? ?? '');
  var spellCastingTime = data['castingTime'] as String? ?? '';
  final spellDurationController = TextEditingController(text: data['duration'] as String? ?? '');

  // Способность
  final abilitySourceController = TextEditingController(text: data['source'] as String? ?? '');

  // Общее поле описания — есть у всех типов.
  final descriptionController = TextEditingController(text: data['description'] as String? ?? '');

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(existing == null
            ? 'Новый объект библиотеки'
            : 'Изменить ${LibraryTypeLabels.singular(type).toLowerCase()}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Название'),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              if (existing == null)
                DropdownButtonFormField<LibraryItemType>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'Тип'),
                  items: [
                    for (final t in LibraryItemType.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(LibraryTypeLabels.singular(t)),
                      ),
                  ],
                  onChanged: (value) => setState(() => type = value ?? type),
                )
              else
                Row(
                  children: [
                    Icon(LibraryTypeLabels.icon(type), size: 18, color: AppTheme.textSecondary),
                    const SizedBox(width: 8),
                    Text(LibraryTypeLabels.singular(type),
                        style: const TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              const SizedBox(height: 10),
              ..._typeFields(
                type: type,
                setState: setState,
                itemCategory: itemCategory,
                onItemCategoryChanged: (v) => itemCategory = v,
                itemWeightController: itemWeightController,
                spellLevelController: spellLevelController,
                spellSchoolController: spellSchoolController,
                spellRangeController: spellRangeController,
                spellComponentsController: spellComponentsController,
                spellCastingTime: spellCastingTime,
                onSpellCastingTimeChanged: (v) => spellCastingTime = v,
                spellDurationController: spellDurationController,
                abilitySourceController: abilitySourceController,
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Описание'),
                maxLines: 3,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sourceUrlController,
                decoration: const InputDecoration(labelText: 'Ссылка на источник (необязательно)'),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
                provider.deleteItem(existing.id!);
              },
              child: const Text('Удалить', style: TextStyle(color: AppTheme.danger)),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );

  if (saved != true || !context.mounted) return;
  if (nameController.text.trim().isEmpty) return;

  final Map<String, dynamic> newData;
  switch (type) {
    case LibraryItemType.item:
      newData = {
        'category': itemCategory,
        'weight': double.tryParse(itemWeightController.text.trim()) ?? 0,
        'description': descriptionController.text.trim(),
      };
      break;
    case LibraryItemType.spell:
      newData = {
        'level': int.tryParse(spellLevelController.text.trim()) ?? 0,
        'school': spellSchoolController.text.trim(),
        'range': spellRangeController.text.trim(),
        'components': spellComponentsController.text.trim(),
        'castingTime': spellCastingTime,
        'duration': spellDurationController.text.trim(),
        'description': descriptionController.text.trim(),
      };
      break;
    case LibraryItemType.ability:
      newData = {
        'source': abilitySourceController.text.trim(),
        'description': descriptionController.text.trim(),
      };
      break;
    case LibraryItemType.other:
      newData = {'description': descriptionController.text.trim()};
      break;
  }

  final now = DateTime.now();
  if (existing == null) {
    await provider.addItem(LibraryItemModel(
      type: type,
      name: nameController.text.trim(),
      data: newData,
      sourceUrl: sourceUrlController.text.trim(),
      createdAt: now,
      updatedAt: now,
    ));
  } else {
    await provider.updateItem(existing.copyWith(
      name: nameController.text.trim(),
      data: newData,
      sourceUrl: sourceUrlController.text.trim(),
    ));
  }
}

/// Возвращает поля формы, специфичные для типа объекта, плюс SizedBox-отступ
/// после блока (общие поля "Описание"/"Ссылка" добавляются в вызывающем коде).
List<Widget> _typeFields({
  required LibraryItemType type,
  required StateSetter setState,
  required String itemCategory,
  required ValueChanged<String> onItemCategoryChanged,
  required TextEditingController itemWeightController,
  required TextEditingController spellLevelController,
  required TextEditingController spellSchoolController,
  required TextEditingController spellRangeController,
  required TextEditingController spellComponentsController,
  required String spellCastingTime,
  required ValueChanged<String> onSpellCastingTimeChanged,
  required TextEditingController spellDurationController,
  required TextEditingController abilitySourceController,
}) {
  switch (type) {
    case LibraryItemType.item:
      return [
        DropdownButtonFormField<String>(
          value: itemCategory,
          decoration: const InputDecoration(labelText: 'Категория'),
          items: _itemCategories
              .map((c) => DropdownMenuItem(value: c, child: Text(_itemCategoryLabel(c))))
              .toList(),
          onChanged: (value) => setState(() => onItemCategoryChanged(value ?? itemCategory)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: itemWeightController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Вес (фунты)'),
        ),
        const SizedBox(height: 10),
      ];
    case LibraryItemType.spell:
      return [
        Row(children: [
          Expanded(
            child: TextField(
              controller: spellLevelController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Уровень (0 = заговор)'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: spellSchoolController,
              decoration: const InputDecoration(labelText: 'Школа/тип'),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: TextField(
              controller: spellRangeController,
              decoration: const InputDecoration(labelText: 'Дальность'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: spellCastingTime.isEmpty ? null : spellCastingTime,
              decoration: const InputDecoration(labelText: 'Время накладывания'),
              items: [
                ..._castingTimes.map((v) => DropdownMenuItem(value: v, child: Text(v))),
                if (spellCastingTime.isNotEmpty && !_castingTimes.contains(spellCastingTime))
                  DropdownMenuItem(value: spellCastingTime, child: Text(spellCastingTime)),
              ],
              onChanged: (value) =>
                  setState(() => onSpellCastingTimeChanged(value ?? spellCastingTime)),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: spellDurationController,
          decoration: const InputDecoration(labelText: 'Длительность'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: spellComponentsController,
          decoration: const InputDecoration(labelText: 'Компоненты (В, С, М)'),
        ),
        const SizedBox(height: 10),
      ];
    case LibraryItemType.ability:
      return [
        TextField(
          controller: abilitySourceController,
          decoration: const InputDecoration(labelText: 'Источник (класс/раса/талант)'),
        ),
        const SizedBox(height: 10),
      ];
    case LibraryItemType.other:
      return const [];
  }
}
