import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/battle/dice_service.dart';

Future<DiceRollResult?> showDiceRoller(
  BuildContext context, {
  DiceService? service,
}) async {
  final dice = service ?? DiceService();
  final expression = TextEditingController(text: '1к20');

  final result = await showModalBottomSheet<DiceRollResult>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Бросок кубиков',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Локальный бросок. История и совместные броски не сохраняются.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: expression,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Выражение',
              hintText: '1к20 + 5',
            ),
            onSubmitted: (_) => _roll(context, dice, expression),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final value in const ['к4', 'к6', 'к8', 'к10', 'к12', 'к20', 'к100'])
                ActionChip(
                  label: Text(value),
                  onPressed: () => expression.text = '1$value',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _roll(context, dice, expression),
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Бросить'),
            ),
          ),
        ],
      ),
    ),
  );

  expression.dispose();
  return result;
}

void _roll(
  BuildContext context,
  DiceService service,
  TextEditingController controller,
) {
  try {
    final result = service.roll(controller.text);
    Navigator.pop(context, result);
  } catch (error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$error')),
    );
  }
}
