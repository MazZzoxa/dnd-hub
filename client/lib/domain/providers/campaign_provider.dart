import 'package:flutter/foundation.dart';

import '../../data/models/campaign_member_model.dart';
import '../../data/models/campaign_model.dart';
import '../campaign/campaign_service.dart';

class CampaignProvider extends ChangeNotifier {
  final CampaignService _service;
  List<CampaignModel> _campaigns = [];
  List<CampaignMemberModel> _members = [];
  CampaignModel? _selected;
  bool _loading = false;

  CampaignProvider({CampaignService? service}) : _service = service ?? CampaignService();

  List<CampaignModel> get campaigns => List.unmodifiable(_campaigns);
  List<CampaignMemberModel> get members => List.unmodifiable(_members);
  CampaignModel? get selected => _selected;
  bool get loading => _loading;

  Future<void> loadCampaigns() async {
    _loading = true;
    notifyListeners();
    _campaigns = await _service.getCampaigns();
    _loading = false;
    notifyListeners();
  }

  Future<void> selectCampaign(CampaignModel campaign) async {
    _selected = campaign;
    _members = campaign.id == null ? [] : await _service.getMembers(campaign.id!);
    notifyListeners();
  }

  void clearSelection() {
    _selected = null;
    _members = [];
    notifyListeners();
  }

  Future<void> createCampaign({required String name, required String description, required String gmName}) async {
    final id = await _service.createCampaign(name: name, description: description, gmName: gmName);
    await loadCampaigns();
    final campaign = _campaigns.firstWhere((c) => c.id == id);
    await selectCampaign(campaign);
  }

  Future<void> saveCampaign({required String name, required String description}) async {
    final campaign = _selected;
    if (campaign == null) return;
    final updated = campaign.copyWith(name: name, description: description);
    await _service.updateCampaign(updated);
    await loadCampaigns();
    _selected = _campaigns.firstWhere((c) => c.id == campaign.id);
    await _reloadMembers();
  }

  Future<void> deleteSelected() async {
    final id = _selected?.id;
    if (id == null) return;
    await _service.deleteCampaign(id);
    clearSelection();
    await loadCampaigns();
  }

  Future<void> addPlayer(String name) async {
    final id = _selected?.id;
    if (id == null) return;
    await _service.addPlayer(campaignId: id, name: name);
    await _reloadMembers();
  }

  Future<void> saveMember(CampaignMemberModel member) async {
    await _service.updateMember(member);
    await _reloadMembers();
  }

  Future<void> replaceGm(int memberId) async {
    final id = _selected?.id;
    if (id == null) return;
    await _service.replaceGm(campaignId: id, newGmMemberId: memberId);
    await _reloadMembers();
  }

  Future<void> removeMember(CampaignMemberModel member) async {
    await _service.removeMember(member);
    await _reloadMembers();
  }

  Future<List<Map<String, dynamic>>> membershipsForCharacter(int characterId) => _service.getMembershipsForCharacter(characterId);

  Future<void> linkCharacter(CampaignMemberModel member, int? characterId) async {
    await _service.linkCharacter(memberId: member.id!, characterId: characterId);
    await _reloadMembers();
  }

  Future<void> _reloadMembers() async {
    final id = _selected?.id;
    if (id == null) return;
    _members = await _service.getMembers(id);
    notifyListeners();
  }
}
