import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/note_model.dart';
import '../../../domain/providers/character_provider.dart';
import '../../../domain/providers/note_provider.dart';

/// Раздел личных заметок игрока — см. п.19 ТЗ.
class NotesSection extends StatefulWidget {
  const NotesSection({super.key});

  @override
  State<NotesSection> createState() => _NotesSectionState();
}

class _NotesSectionState extends State<NotesSection> {
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
        context.read<NoteProvider>().loadForCharacter(characterId);
      });
    }

    return Consumer<NoteProvider>(
      builder: (context, provider, _) {
        if (provider.loading) {
          return const Center(child: CircularProgressIndicator());
        }
        return Stack(
          children: [
            if (provider.notes.isEmpty)
              const Center(
                child:
                    Text('Заметок пока нет', style: TextStyle(color: AppTheme.textSecondary)),
              )
            else
              ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                itemCount: provider.notes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final note = provider.notes[index];
                  return Dismissible(
                    key: ValueKey(note.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.danger,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (_) => provider.deleteNote(note.id!),
                    child: Material(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => _showNoteDialog(
                          context,
                          characterId: characterId,
                          existing: note,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (note.title.isNotEmpty)
                                Text(note.title,
                                    style:
                                        const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                              if (note.title.isNotEmpty) const SizedBox(height: 4),
                              Text(note.content,
                                  maxLines: 4, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Text(
                                _formatDate(note.createdAt),
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.textSecondary),
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
                onPressed: () => _showNoteDialog(context, characterId: characterId),
                child: const Icon(Icons.add),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _formatDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)}.${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  static Future<void> _showNoteDialog(
    BuildContext context, {
    required int characterId,
    NoteModel? existing,
  }) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final contentController = TextEditingController(text: existing?.content ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Новая заметка' : 'Изменить заметку'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Заголовок (необязательно)'),
                autofocus: true,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: contentController,
                decoration: const InputDecoration(labelText: 'Текст заметки'),
                maxLines: 6,
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
                    title: const Text('Удалить заметку?'),
                    content: const Text('Заметка будет удалена без возможности восстановления.'),
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
                  await context.read<NoteProvider>().deleteNote(existing.id!);
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
    if (contentController.text.trim().isEmpty) return;

    final provider = context.read<NoteProvider>();
    if (existing == null) {
      await provider.addNote(NoteModel(
        characterId: characterId,
        title: titleController.text.trim(),
        content: contentController.text.trim(),
        createdAt: DateTime.now(),
      ));
    } else {
      await provider.updateNote(existing.copyWith(
        title: titleController.text.trim(),
        content: contentController.text.trim(),
      ));
    }
  }
}
