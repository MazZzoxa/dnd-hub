import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_hub/domain/battle/dice_service.dart';

class _FixedRandom implements Random {
  final int value;
  const _FixedRandom(this.value);

  @override
  bool nextBool() => value.isOdd;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => value.clamp(0, max - 1).toInt();
}

void main() {
  test('supports Russian к dice notation', () {
    final result = DiceService(random: const _FixedRandom(2)).roll('2к6+3');
    expect(result.expression, '2к6+3');
    expect(result.rolls, [3, 3]);
    expect(result.total, 9);
  });

  test('keeps compatibility with d notation', () {
    final result = DiceService(random: const _FixedRandom(1)).roll('1d20+5');
    expect(result.rolls, [2]);
    expect(result.total, 7);
  });
}
