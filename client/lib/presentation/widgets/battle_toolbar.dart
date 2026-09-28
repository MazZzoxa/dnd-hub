import 'package:flutter/material.dart';

class BattleToolbar extends StatelessWidget {
  final VoidCallback onDice;
  final VoidCallback? onEndBattle;
  final bool canEndBattle;

  const BattleToolbar({
    super.key,
    required this.onDice,
    this.onEndBattle,
    required this.canEndBattle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onDice,
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Кубики'),
            ),
            if (canEndBattle)
              OutlinedButton.icon(
                onPressed: onEndBattle,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Завершить бой'),
              ),
          ],
        ),
      ),
    );
  }
}
