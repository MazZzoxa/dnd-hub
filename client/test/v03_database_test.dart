import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_hub/data/database/database_helper.dart';

void main() {
  test('v0.3 schema exposes campaign and XP tables', () async {
    final db = await DatabaseHelper.instance.database;
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final names = tables.map((row) => row['name'] as String).toSet();
    expect(names, containsAll(<String>{'campaigns', 'campaign_members', 'xp_transactions'}));
    await DatabaseHelper.instance.close();
  });
}
