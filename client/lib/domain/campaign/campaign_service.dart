import 'package:sqflite/sqflite.dart';

import '../../data/database/database_helper.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/campaign_model.dart';
import '../../data/repositories/campaign_repository.dart';

class CampaignService {
  final CampaignRepository _repository;

  CampaignService({CampaignRepository? repository}) : _repository = repository ?? CampaignRepository();

  Future<int> createCampaign({required String name, String description = '', required String gmName, String clientId = ''}) async {
    final cleanName = name.trim();
    final cleanGm = gmName.trim();
    if (cleanName.isEmpty) throw ArgumentError.value(name, 'name', 'Название кампании обязательно.');
    if (cleanGm.isEmpty) throw ArgumentError.value(gmName, 'gmName', 'Имя GM обязательно.');
    final now = DateTime.now();
    final campaign = CampaignModel(name: cleanName, description: description.trim(), createdAt: now, updatedAt: now);
    final gm = CampaignMemberModel(campaignId: 0, name: cleanGm, role: CampaignRole.gm, clientId: clientId, createdAt: now);
    try {
      return await _repository.create(campaign, gm);
    } on DatabaseException catch (e) {
      throw StateError('Не удалось создать кампанию: ${e.toString()}');
    }
  }

  Future<void> updateCampaign(CampaignModel campaign) async {
    if (campaign.id == null) throw StateError('Кампания должна иметь id.');
    final name = campaign.name.trim();
    if (name.isEmpty) throw ArgumentError.value(campaign.name, 'name', 'Название кампании обязательно.');
    await _repository.update(campaign.copyWith(name: name, description: campaign.description.trim(), updatedAt: DateTime.now()));
  }

  Future<void> deleteCampaign(int id) => _repository.delete(id);

  Future<List<CampaignModel>> getCampaigns() => _repository.getAll();
  Future<CampaignModel?> getById(int id) => _repository.getById(id);
  Future<List<CampaignMemberModel>> getMembers(int campaignId) => _repository.getMembers(campaignId);
  Future<List<Map<String, dynamic>>> getMembershipsForCharacter(int characterId) => _repository.getMembershipsForCharacter(characterId);

  Future<int> addPlayer({required int campaignId, required String name}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError.value(name, 'name', 'Имя участника обязательно.');
    return _repository.addMember(CampaignMemberModel(
      campaignId: campaignId,
      name: cleanName,
      role: CampaignRole.player,
      createdAt: DateTime.now(),
    ));
  }


  Future<int> addNetworkPlayer({required int campaignId, required String clientId, required String name}) async {
    final cleanName = name.trim().isEmpty ? 'Player' : name.trim();
    final db = await DatabaseHelper.instance.database;
    final existing = await db.query(
      'campaign_members',
      where: 'campaign_id = ? AND client_id = ? AND role = ?',
      whereArgs: [campaignId, clientId, 'player'],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await db.update(
        'campaign_members',
        {'name': cleanName},
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
      return existing.first['id'] as int;
    }
    return _repository.addMember(CampaignMemberModel(
      campaignId: campaignId,
      name: cleanName,
      role: CampaignRole.player,
      clientId: clientId,
      createdAt: DateTime.now(),
    ));
  }

  Future<CampaignMemberModel?> getMemberForClient({required int campaignId, required String clientId}) async {
    final members = await _repository.getMembers(campaignId);
    for (final member in members) {
      if (member.clientId == clientId) return member;
    }
    return null;
  }

  Future<void> updateMember(CampaignMemberModel member) async {
    if (member.id == null) throw StateError('Участник должен иметь id.');
    final members = await _repository.getMembers(member.campaignId);
    final previous = members.firstWhere((m) => m.id == member.id);
    if (member.role == CampaignRole.player && previous.role == CampaignRole.gm) {
      throw StateError('В кампании должен оставаться ровно один GM. Сначала назначьте нового GM.');
    }
    final gmCount = members.where((m) => m.role == CampaignRole.gm).length;
    if (member.role == CampaignRole.gm && previous.role != CampaignRole.gm && gmCount >= 1) {
      throw StateError('В кампании может быть только один GM.');
    }
    final cleanName = member.name.trim();
    if (cleanName.isEmpty) throw ArgumentError.value(member.name, 'name', 'Имя участника обязательно.');
    await _repository.updateMember(member.copyWith(name: cleanName));
  }

  Future<void> replaceGm({required int campaignId, required int newGmMemberId}) async {
    final db = await DatabaseHelper.instance.database;
    await db.transaction((txn) async {
      final members = await txn.query('campaign_members', where: 'campaign_id = ?', whereArgs: [campaignId]);
      final target = members.where((m) => m['id'] == newGmMemberId).toList();
      if (target.isEmpty) throw StateError('Участник не найден.');
      await txn.update('campaign_members', {'role': 'player'}, where: 'campaign_id = ? AND role = ?', whereArgs: [campaignId, 'gm']);
      await txn.update('campaign_members', {'role': 'gm'}, where: 'id = ?', whereArgs: [newGmMemberId]);
    });
  }

  Future<void> removeMember(CampaignMemberModel member) async {
    if (member.id == null) throw StateError('Участник должен иметь id.');
    if (member.role == CampaignRole.gm) {
      throw StateError('Нельзя удалить единственного GM. Сначала назначьте нового GM.');
    }
    await _repository.deleteMember(member.id!);
  }

  Future<void> linkCharacter({required int memberId, required int? characterId}) async {
    final db = await DatabaseHelper.instance.database;
    final rows = await db.query('campaign_members', where: 'id = ?', whereArgs: [memberId], limit: 1);
    if (rows.isEmpty) throw StateError('Участник не найден.');
    final campaignId = rows.first['campaign_id'] as int;
    final conflict = characterId == null
        ? const <Map<String, Object?>>[]
        : await db.query('campaign_members', where: 'campaign_id = ? AND linked_character_id = ? AND id != ?', whereArgs: [campaignId, characterId, memberId], limit: 1);
    if (conflict.isNotEmpty) throw StateError('Этот персонаж уже привязан к другому участнику этой кампании.');
    await db.update('campaign_members', {'linked_character_id': characterId}, where: 'id = ?', whereArgs: [memberId]);
  }
}
