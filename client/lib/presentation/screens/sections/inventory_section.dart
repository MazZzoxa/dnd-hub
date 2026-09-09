import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/item_model.dart';
import '../../../domain/providers/character_provider.dart';
import '../../../domain/providers/inventory_provider.dart';

const _categories = ['Weapons', 'Armor', 'Consumables', 'Other'];

const _categoryLabels = <String, String>{
  'Weapons': 'Оружие',
  'Armor': 'Броня',
  'Consumables': 'Расходуемые предметы',
  'Other': 'Прочее',
};

String _categoryLabel(String category) => _categoryLabels[category] ?? category;

/// Раздел инвентаря — см. п.16 ТЗ.
/// Предметы сгруппированы по категориям, количество меняется кнопками [-][+].
class InventorySection extends StatefulWidget {
  const InventorySection({super.key});

  @override
  State<InventorySection> createState() => _InventorySectionState();
}

class _InventorySectionState extends State<InventorySection> {
  int? _loadedForCharacterId;

  @override
  Widget build(BuildContext context) {
    final characterId = context.watch<CharacterProvider>().selected?.id;
    if (characterId == null) {
      return const Center(child: Text('Персонаж не выбран'));
    }
    if (_loadedForCharacterId != characterId) {
      _loadedForCharacterId = characterId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<InventoryProvider>().loadForCharacter(characterId);
      });
    }

    return Consumer<InventoryProvider>(
      builder: (context, provider, _) {
        if (provider.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        final grouped = provider.itemsByCategory;
        return Stack(
          children: [
            if (provider.items.isEmpty)
              const Center(
                child: Text('Инвентарь пуст', style: TextStyle(color: AppTheme.textSecondary)),
              )
            else
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  for (final category in _categories)
                    if (grouped[category]?.isNotEmpty == true)
                      _CategoryBlock(
                        category: category,
                        items: grouped[category]!,
                        characterId: characterId,
                      ),
                  for (final entry in grouped.entries)
                    if (!_categories.contains(entry.key))
                      _CategoryBlock(
                        category: entry.key,
                        items: entry.value,
                        characterId: characterId,
                      ),
                ],
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: FloatingActionButton(
                onPressed: () => _showItemDialog(context, characterId: characterId),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _showItemDialog(
    BuildContext context, {
    required int characterId,
    ItemModel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final quantityController =
        TextEditingController(text: '${existing?.quantity ?? 1}');
    final weightController =
        TextEditingController(text: existing?.weight != null ? '${existing!.weight}' : '0');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    String category = existing?.category ?? _categories.first;

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(existing == null ? 'Новый предмет' : 'Изменить предмет'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Название'),
                  autofocus: true,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(labelText: 'Категория'),
                  items: _categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c))))
                      .toList(),
                  onChanged: (value) => setState(() => category = value ?? category),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Количество'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: weightController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Вес'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(labelText: 'Описание'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
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

    final item = ItemModel(
      id: existing?.id,
      characterId: characterId,
      name: nameController.text.trim(),
      category: category,
      quantity: int.tryParse(quantityController.text.trim()) ?? 1,
      weight: double.tryParse(weightController.text.trim()) ?? 0,
      description: descriptionController.text.trim(),
    );

    final provider = context.read<InventoryProvider>();
    if (existing == null) {
      await provider.addItem(item);
    } else {
      await provider.updateItem(item);
    }
  }
}

class _CategoryBlock extends StatelessWidget {
  final String category;
  final List<ItemModel> items;
  final int characterId;

  const _CategoryBlock({
    required this.category,
    required this.items,
    required this.characterId,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(_categoryLabel(category),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textSecondary)),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (int i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                  _ItemRow(item: items[i], characterId: characterId),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final ItemModel item;
  final int characterId;

  const _ItemRow({required this.item, required this.characterId});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<InventoryProvider>();
    return ListTile(
      onTap: () => _InventorySectionState._showItemDialog(
        context,
        characterId: characterId,
        existing: item,
      ),
      title: Text(item.name),
      subtitle: item.description.isNotEmpty ? Text(item.description) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () => provider.adjustQuantity(item, -1),
          ),
          SizedBox(
            width: 26,
            child: Text('${item.quantity}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => provider.adjustQuantity(item, 1),
          ),
        ],
      ),
    );
  }
}
