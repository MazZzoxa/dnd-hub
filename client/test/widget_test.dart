import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_hub/main.dart';

void main() {
  testWidgets('D&D Hub launches', (tester) async {
    await tester.pumpWidget(const DndHubApp());

    expect(find.text('D&D Hub'), findsOneWidget);
    expect(find.text('Новый персонаж'), findsOneWidget);
  });
}
