import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Строка-переход в раздел персонажа (Inventory / Spells / Abilities / Notes)
/// — см. мокап телефона в п.12 ТЗ ("🎒 Inventory   →").
class SectionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? trailingText;
  final VoidCallback onTap;

  const SectionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.trailingText,
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.accent),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
              ),
              if (trailingText != null) ...[
                Text(trailingText!,
                    style: const TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
