import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/providers/character_provider.dart';
import '../character_form_screen.dart';

/// Раздел настроек персонажа первой версии: редактирование основных данных
/// и удаление персонажа. Общие настройки приложения (тема и т.д.) — вне
/// рамок Version 0.1.
class SettingsSection extends StatelessWidget {
  final VoidCallback? onCharacterDeleted;

  const SettingsSection({super.key, this.onCharacterDeleted});

  @override
  Widget build(BuildContext context) {
    return Consumer<CharacterProvider>(
      builder: (context, provider, _) {
        final character = provider.selected;
        if (character == null) {
          return const Center(child: Text('Персонаж не выбран'));
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Tile(
              icon: Icons.edit,
              label: 'Редактировать персонажа',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CharacterFormScreen(existing: character),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _Tile(
              icon: Icons.delete_outline,
              label: 'Удалить персонажа',
              color: AppTheme.danger,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Удалить персонажа?'),
                    content: Text(
                        '«${character.name}» будет удалён без возможности восстановления.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Отмена'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Удалить',
                            style: TextStyle(color: AppTheme.danger)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && character.id != null && context.mounted) {
                  await provider.deleteCharacter(character.id!);
                  onCharacterDeleted?.call();
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _Tile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: color ?? AppTheme.accent),
              const SizedBox(width: 14),
              Text(label,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
