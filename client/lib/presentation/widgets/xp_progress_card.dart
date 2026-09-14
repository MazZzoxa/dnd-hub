import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/xp/xp_progress.dart';

class XpProgressCard extends StatelessWidget {
  final XpProgress progress;
  final VoidCallback onHistory;

  const XpProgressCard({super.key, required this.progress, required this.onHistory});

  @override
  Widget build(BuildContext context) {
    final next = progress.nextLevelXp;
    final text = next == null
        ? '${progress.currentXp} XP · максимальный уровень'
        : '${progress.currentXp} / $next XP';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.star, color: AppTheme.accent),
            const SizedBox(width: 8),
            Text('Опыт · уровень ${progress.level}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const Spacer(),
            IconButton(onPressed: onHistory, tooltip: 'История XP', icon: const Icon(Icons.history)),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress.progress, minHeight: 8),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ]),
      ),
    );
  }
}
