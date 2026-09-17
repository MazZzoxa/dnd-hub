import 'package:flutter_test/flutter_test.dart';
import 'package:dnd_hub/data/database/database_helper.dart';
import 'package:dnd_hub/data/models/campaign_model.dart';
import 'package:dnd_hub/data/repositories/campaign_repository.dart';
import 'package:dnd_hub/data/models/campaign_member_model.dart';
import 'package:dnd_hub/domain/providers/session_provider.dart';

void main() {
  test('v0.4 schema exposes campaign sessions and supports a session lifecycle', () async {
    final db = await DatabaseHelper.instance.database;
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final names = tables.map((row) => row['name'] as String).toSet();
    expect(names, contains('campaign_sessions'));

    final now = DateTime.now();
    final campaign = CampaignModel(name: 'v0.4 Test', createdAt: now, updatedAt: now);
    final campaignId = await CampaignRepository().create(
      campaign,
      CampaignMemberModel(campaignId: 0, name: 'GM', role: CampaignRole.gm, createdAt: now),
    );

    final provider = SessionProvider();
    await provider.startSession(campaignId: campaignId, title: 'Session 1');
    expect(provider.active, isNotNull);
    expect(provider.active!.title, 'Session 1');

    await provider.updateActive(notes: 'Test notes');
    expect(provider.active!.notes, 'Test notes');

    await provider.completeActive();
    expect(provider.active, isNull);
    expect(provider.sessions.any((session) => session.title == 'Session 1' && session.notes == 'Test notes'), isTrue);

    await db.delete('campaigns', where: 'id = ?', whereArgs: [campaignId]);
    await DatabaseHelper.instance.close();
  });
}
