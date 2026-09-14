import '../database/database_helper.dart';
import '../models/campaign_model.dart';
import '../models/campaign_member_model.dart';

class CampaignRepository {
  final DatabaseHelper _database = DatabaseHelper.instance;

  Future<List<CampaignModel>> getAll() async {
    final db = await _database.database;
    final rows = await db.query('campaigns', orderBy: 'name COLLATE NOCASE');
    return rows.map(CampaignModel.fromMap).toList();
  }

  Future<CampaignModel?> getById(int id) async {
    final db = await _database.database;
    final rows = await db.query('campaigns', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : CampaignModel.fromMap(rows.first);
  }

  Future<List<CampaignMemberModel>> getMembers(int campaignId) async {
    final db = await _database.database;
    final rows = await db.query('campaign_members', where: 'campaign_id = ?', whereArgs: [campaignId], orderBy: "CASE role WHEN 'gm' THEN 0 ELSE 1 END, name COLLATE NOCASE");
    return rows.map(CampaignMemberModel.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getMembershipsForCharacter(int characterId) async {
    final db = await _database.database;
    return db.rawQuery('''
      SELECT c.id AS campaign_id, c.name AS campaign_name,
             m.id AS member_id, m.name AS member_name, m.role AS role
      FROM campaign_members m
      JOIN campaigns c ON c.id = m.campaign_id
      WHERE m.linked_character_id = ?
      ORDER BY c.name COLLATE NOCASE
    ''', [characterId]);
  }

  Future<int> create(CampaignModel campaign, CampaignMemberModel gm) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final campaignId = await txn.insert('campaigns', campaign.toMap()..remove('id'));
      await txn.insert('campaign_members', gm.copyWith(campaignId: campaignId).toMap()..remove('id'));
      return campaignId;
    });
  }

  Future<void> update(CampaignModel campaign) async {
    final db = await _database.database;
    await db.update('campaigns', campaign.toMap()..remove('id'), where: 'id = ?', whereArgs: [campaign.id]);
  }

  Future<void> delete(int id) async {
    final db = await _database.database;
    await db.delete('campaigns', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addMember(CampaignMemberModel member) async {
    final db = await _database.database;
    return db.insert('campaign_members', member.toMap()..remove('id'));
  }

  Future<void> updateMember(CampaignMemberModel member) async {
    final db = await _database.database;
    await db.update('campaign_members', member.toMap()..remove('id'), where: 'id = ?', whereArgs: [member.id]);
  }

  Future<void> deleteMember(int id) async {
    final db = await _database.database;
    await db.delete('campaign_members', where: 'id = ?', whereArgs: [id]);
  }
}
