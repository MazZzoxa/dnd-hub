import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/import_file_dialog.dart';
import '../widgets/import_url_dialog.dart';
import '../../data/models/character_model.dart';
import '../../domain/providers/character_provider.dart';
import '../../data/export/export_manager.dart';
import '../../data/import/import_manager.dart';
import '../widgets/export_format_dialog.dart';
import 'character_form_screen.dart';
import 'character_home_screen.dart';
import 'library_screen.dart';

/// Первый экран приложения: список сохранённых персонажей.
/// Позволяет создать нового персонажа или открыть существующего.
class CharacterListScreen extends StatefulWidget {
  const CharacterListScreen({super.key});

  @override
  State<CharacterListScreen> createState() => _CharacterListScreenState();
}

class _CharacterListScreenState extends State<CharacterListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CharacterProvider>().loadCharacters();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('D&D Hub'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Импортировать файл',
            onPressed: () async {
              final result = await showImportFileDialog(context);
              if (!mounted || result == null) return;
              if (result.importedCharacterId != null) {
                await context.read<CharacterProvider>().loadCharacters();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.link_outlined),
            tooltip: 'Импортировать по ссылке',
            onPressed: () async {
              final result = await showImportUrlDialog(context);
              if (!mounted || result == null) return;
              if (result.importedCharacterId != null) {
                await context.read<CharacterProvider>().loadCharacters();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.auto_stories_outlined),
            tooltip: 'Библиотека',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LibraryScreen()),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Резервное копирование',
            onSelected: (value) async {
              if (value == 'backup') {
                await _createBackup(context);
              } else if (value == 'restore') {
                await _restoreBackup(context);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'backup',
                child: ListTile(
                  leading: Icon(Icons.backup_outlined),
                  title: Text('Создать backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: ListTile(
                  leading: Icon(Icons.restore_outlined),
                  title: Text('Восстановить backup'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Consumer<CharacterProvider>(
        builder: (context, provider, _) {
          if (provider.loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (provider.characters.isEmpty) {
            return _EmptyState(onCreate: () => _openCreate(context));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: provider.characters.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final character = provider.characters[index];
              return _CharacterCard(
                character: character,
                onTap: () => _openCharacter(context, character),
                onExport: () => _exportCharacter(context, character),
                onDelete: () => _confirmDelete(context, character),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('Новый персонаж'),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CharacterFormScreen()),
    );
  }

  void _openCharacter(BuildContext context, CharacterModel character) {
    context.read<CharacterProvider>().selectCharacter(character);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CharacterHomeScreen()),
    );
  }


  Future<void> _createBackup(BuildContext context) async {
    try {
      final path = await ExportManager().exportBackup();
      if (!context.mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup сохранён: $path')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать backup: $error')),
      );
    }
  }

  Future<void> _restoreBackup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Восстановить backup?'),
        content: const Text(
          'Текущие локальные данные D&D Hub будут полностью заменены данными из backup. '
          'Перед восстановлением рекомендуется сделать backup текущего состояния.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['dndhub'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !context.mounted) return;

    final bytes = picked.files.single.bytes;
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось прочитать backup-файл.')),
      );
      return;
    }

    try {
      final manager = ImportManager();
      final typedBytes = Uint8List.fromList(bytes);
      final preview = manager.previewBytes(typedBytes);
      if (preview.exportType != 'backup') {
        throw const ImportFormatException('Выбранный файл не является backup D&D Hub.');
      }

      final result = await manager.importBytes(typedBytes);
      if (!context.mounted) return;
      final characters = context.read<CharacterProvider>();
      characters.clearSelection();
      await characters.loadCharacters();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.title)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось восстановить backup: $error')),
      );
    }
  }

  Future<void> _exportCharacter(BuildContext context, CharacterModel character) async {
    final format = await showExportFormatDialog(context);
    if (format == null || !context.mounted) return;

    try {
      final fileName = await ExportManager().exportCharacter(character, format: format);
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

  Future<void> _confirmDelete(BuildContext context, CharacterModel character) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить персонажа?'),
        content: Text('«${character.name}» будет удалён без возможности восстановления.'),
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
    if (confirmed == true && character.id != null) {
      if (context.mounted) {
        await context.read<CharacterProvider>().deleteCharacter(character.id!);
      }
    }
  }
}

class _CharacterCard extends StatelessWidget {
  final CharacterModel character;
  final VoidCallback onTap;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _CharacterCard({
    required this.character,
    required this.onTap,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppTheme.primary.withOpacity(0.2),
                child: Text(
                  character.name.isNotEmpty ? character.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(character.name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      '${character.race} · ${character.className} · Ур. ${character.level}',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text('${character.hp}/${character.maxHp} хиты',
                  style: const TextStyle(color: AppTheme.textSecondary)),
              PopupMenuButton<String>(
                tooltip: 'Действия',
                onSelected: (value) {
                  if (value == 'export') onExport();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'export',
                    child: ListTile(leading: Icon(Icons.file_upload_outlined), title: Text('Экспортировать'), contentPadding: EdgeInsets.zero),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Удалить'), contentPadding: EdgeInsets.zero),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyState({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield_outlined, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          const Text('Пока нет персонажей', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Создайте своего первого героя',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Создать персонажа'),
          ),
        ],
      ),
    );
  }
}
