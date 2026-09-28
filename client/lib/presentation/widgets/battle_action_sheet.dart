import 'package:flutter/material.dart';

enum BattleActionKind { damage, heal, temporaryHp }

Future<int?> showBattleActionSheet(
  BuildContext context, {
  required BattleActionKind kind,
  required String characterName,
}) async {
  final controller = TextEditingController();
  final title = switch (kind) {
    BattleActionKind.damage => 'Урон · $characterName',
    BattleActionKind.heal => 'Лечение · $characterName',
    BattleActionKind.temporaryHp => 'Временные хиты · $characterName',
  };
  final label = switch (kind) {
    BattleActionKind.damage => 'Количество урона',
    BattleActionKind.heal => 'Количество лечения',
    BattleActionKind.temporaryHp => 'Новое значение временных хитов',
  };

  final result = await showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final value = int.tryParse(controller.text.trim());
            if (value == null || value < 0) return;
            Navigator.pop(context, value);
          },
          child: const Text('Применить'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
