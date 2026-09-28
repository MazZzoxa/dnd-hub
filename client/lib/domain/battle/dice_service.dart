import 'dart:math';

class DiceRollResult {
  final String expression;
  final List<int> rolls;
  final int modifier;
  final int total;

  const DiceRollResult({
    required this.expression,
    required this.rolls,
    required this.modifier,
    required this.total,
  });
}

class DiceService {
  final Random _random;

  DiceService({Random? random}) : _random = random ?? Random();

  DiceRollResult roll(String input) {
    final expression = input.trim().replaceAll(RegExp(r'\s+'), '');
    final match =
        RegExp(r'^(\d+)[dDкК](\d+)([+-]\d+)?$').firstMatch(expression);

    if (match == null) {
      throw FormatException(
        'Поддерживаются выражения вроде 1к20, 1к20+5 и 2к6+3.',
      );
    }

    final count = int.parse(match.group(1)!);
    final sides = int.parse(match.group(2)!);
    final modifier = int.tryParse(match.group(3) ?? '0') ?? 0;

    if (count < 1 || count > 100) {
      throw RangeError('Количество кубиков должно быть от 1 до 100.');
    }
    if (sides < 2 || sides > 100) {
      throw RangeError('Количество граней должно быть от 2 до 100.');
    }

    final rolls = [
      for (var i = 0; i < count; i++) _random.nextInt(sides) + 1,
    ];

    return DiceRollResult(
      expression: expression,
      rolls: rolls,
      modifier: modifier,
      total: rolls.fold<int>(0, (sum, value) => sum + value) + modifier,
    );
  }
}
