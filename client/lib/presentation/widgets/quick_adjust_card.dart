import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Карточка для быстро изменяемых параметров: HP / XP / Gold.
/// Соответствует принципу проекта: изменение должно происходить
/// значительно быстрее, чем на бумажном/PDF-листе (см. п.15 ТЗ).
///
/// Поддерживает:
///  - большие кнопки [-] / [+] на шаг `step`
///  - долгое нажатие для быстрого ввода произвольного значения
///  - опциональную вторую строку (напр. current / max для HP)
class QuickAdjustCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final String valueText;
  final Color? accentColor;
  final int step;
  final ValueChanged<int> onAdjust; // передаёт дельту (может быть отрицательной)
  final VoidCallback? onTapValue; // напр. открыть диалог точного ввода

  const QuickAdjustCard({
    super.key,
    required this.label,
    required this.icon,
    required this.valueText,
    required this.onAdjust,
    this.accentColor,
    this.step = 1,
    this.onTapValue,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? AppTheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onTapValue,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary)),
                  Text(
                    valueText,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          _AdjustButton(
            icon: Icons.remove,
            color: color,
            onTap: () => onAdjust(-step),
            onLongPress: () => onAdjust(-step * 5),
          ),
          const SizedBox(width: 8),
          _AdjustButton(
            icon: Icons.add,
            color: color,
            onTap: () => onAdjust(step),
            onLongPress: () => onAdjust(step * 5),
          ),
        ],
      ),
    );
  }
}

class _AdjustButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _AdjustButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.18),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}
