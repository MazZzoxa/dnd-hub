import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/ability_model.dart';
import '../../../data/models/library_item_model.dart';
import '../../../domain/providers/ability_provider.dart';
import '../../../domain/providers/character_provider.dart';
import '../../widgets/add_options_sheet.dart';
import '../../widgets/library_picker.dart';

/// Раздел способностей — см. п.18 ТЗ (классовые/расовые способности, таланты).
class AbilitiesSection extends StatefulWidget {
  const AbilitiesSection({super.key});

  @override
  State<AbilitiesSection> createState() => _AbilitiesSectionState();
}

class _AbilitiesSectionState extends State<AbilitiesSection> {
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
        context.read<AbilityProvider>().loadForCharacter(characterId);
      });
    }

    return Consumer<AbilityProvider>(
      builder: (context, provider, _) {
        if (provider.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          children: [
            if (provider.abilities.isEmpty)
              const Center(
                child: Text('Способности ещё не добавлены',
                    style: TextStyle(color: AppTheme.textSecondary)),
              )
            else
              ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: provider.abilities.length,
                onReorderItem: provider.reorderAbilities,
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final ability = provider.abilities[index];
                  return Padding(
                    key: ValueKey(ability.id),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showAbilityDialog(
                          context,
                          characterId: characterId,
                          existing: ability,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 14, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.only(top: 2, right: 8),
                                  child: Icon(Icons.drag_handle,
                                      color: AppTheme.textSecondary),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(ability.name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600, fontSize: 15)),
                                        ),
                                        if (ability.source.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: AppTheme.surfaceVariant,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(ability.source,
                                                style: const TextStyle(
                                                    fontSize: 11, color: AppTheme.textSecondary)),
                                          ),
                                      ],
                                    ),
                                    if (ability.description.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(ability.description,
                                          style: const TextStyle(color: AppTheme.textSecondary)),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: FloatingActionButton(
                onPressed: () => showAddOptionsSheet(
                  context,
                  onManual: () => _showAbilityDialog(context, characterId: characterId),
                  onFromLibrary: () => _addFromLibrary(context, characterId: characterId),
                ),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _addFromLibrary(BuildContext context, {required int characterId}) async {
    final picked = await showLibraryPickerDialog(context, type: LibraryItemType.ability);
    if (picked == null || !context.mounted) return;

    final data = picked.data;
    final ability = AbilityModel(
      characterId: characterId,
      name: picked.name,
      source: data['source'] as String? ?? '',
      description: data['description'] as String? ?? '',
      libraryItemId: picked.id,
      sourceUrl: picked.sourceUrl,
    );
    await context.read<AbilityProvider>().addAbility(ability);
  }

  static Future<void> _showAbilityDialog(
    BuildContext context, {
    required int characterId,
    AbilityModel? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final sourceController = TextEditingController(text: existing?.source ?? '');
    final descriptionController = TextEditingController(text: existing?.description ?? '');
    final sourceUrlController = TextEditingController(text: existing?.sourceUrl ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Новая способность' : 'Изменить способность'),
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
              TextField(
                controller: sourceController,
                decoration:
                    const InputDecoration(labelText: 'Источник (класс / раса / талант)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Описание'),
                maxLines: 4,
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
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Удалить способность?'),
                    content: Text('«${existing.name}» будет удалена без возможности восстановления.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Удалить', style: TextStyle(color: AppTheme.danger)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  await context.read<AbilityProvider>().deleteAbility(existing.id!);
                  if (context.mounted) Navigator.of(context).pop(false);
                }
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
    );

    if (saved != true || !context.mounted) return;
    if (nameController.text.trim().isEmpty) return;

    final ability = AbilityModel(
      id: existing?.id,
      characterId: characterId,
      name: nameController.text.trim(),
      source: sourceController.text.trim(),
      description: descriptionController.text.trim(),
      sortOrder: existing?.sortOrder ?? 0,
      sourceUrl: sourceUrlController.text.trim(),
    );

    final provider = context.read<AbilityProvider>();
    if (existing == null) {
      await provider.addAbility(ability);
    } else {
      await provider.updateAbility(ability);
    }
  }
}
