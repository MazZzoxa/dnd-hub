import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/campaign_member_model.dart';
import '../../data/models/campaign_model.dart';
import '../campaign/campaign_service.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_service.dart';
import '../../network/connection_manager.dart';

class CampaignProvider extends ChangeNotifier {
  final CampaignService _service;
  final SyncService? _syncService;
  final ConnectionManager? _connectionManager;
  StreamSubscription<NetworkMessage>? _syncSubscription;
  List<CampaignModel> _campaigns = [];
  List<CampaignModel> _ownedCampaigns = [];
  List<CampaignModel> _joinedCampaigns = [];
  List<CampaignMemberModel> _members = [];
  CampaignModel? _selected;
  bool _loading = false;
  Set<int> _playerLinkedCharacterIds = <int>{};

  CampaignProvider({CampaignService? service, SyncService? syncService, ConnectionManager? connectionManager})
      : _service = service ?? CampaignService(),
        _syncService = syncService,
        _connectionManager = connectionManager {
    _syncSubscription = _syncService?.events.listen(_onSyncEvent);
  }

  List<CampaignModel> get campaigns => List.unmodifiable(_campaigns);
  List<CampaignMemberModel> get members => List.unmodifiable(_members);
  CampaignModel? get selected => _selected;
  bool get loading => _loading;

  CampaignMemberModel? get currentMembership {
    if (localClientId.isEmpty) return null;
    for (final member in _members) {
      if (member.clientId == localClientId) return member;
    }
    return null;
  }

  String get localClientId => _connectionManager?.clientId ?? '';

  Future<CampaignRole?> roleForCampaign(CampaignModel campaign) async {
    final id = campaign.id;
    if (id == null || localClientId.isEmpty) return null;
    final member = await _service.getMemberForClient(campaignId: id, clientId: localClientId);
    return member?.role;
  }

  Future<CampaignMemberModel?> membershipForCampaign(CampaignModel campaign) async {
    final id = campaign.id;
    if (id == null || localClientId.isEmpty) return null;
    return _service.getMemberForClient(campaignId: id, clientId: localClientId);
  }

  List<CampaignModel> get ownedCampaigns => List.unmodifiable(_ownedCampaigns);
  List<CampaignModel> get joinedCampaigns => List.unmodifiable(_joinedCampaigns);

  /// Персонажи игроков, привязанные к кампаниям, которыми управляет текущий ГМ.
  /// Они остаются в локальной БД и доступны в GM/Battle интерфейсе, но не
  /// должны отображаться как отдельные локальные персонажи на главном экране.
  Set<int> get playerLinkedCharacterIds =>
      Set.unmodifiable(_playerLinkedCharacterIds);

  Future<void> loadCampaigns() async {
    _loading = true;
    notifyListeners();
    final selectedSyncId = _selected?.syncId;
    _campaigns = _dedupeCampaignCopies(await _service.getCampaigns());
    await _rebuildCategories();
    if (selectedSyncId != null && selectedSyncId.isNotEmpty) {
      final index = _campaigns.indexWhere((campaign) => campaign.syncId == selectedSyncId);
      if (index == -1) {
        _selected = null;
        _members = [];
      } else {
        _selected = _campaigns[index];
      }
    }
    _loading = false;
    notifyListeners();
  }

  List<CampaignModel> _dedupeCampaignCopies(List<CampaignModel> source) {
    final result = <CampaignModel>[];
    final seen = <String, CampaignModel>{};
    for (final campaign in source) {
      final created = campaign.createdAt.toUtc().toIso8601String();
      final exactCopyKey = '${campaign.name}\u0000${campaign.description}\u0000$created';
      final syncKey = campaign.syncId.trim().isEmpty
          ? exactCopyKey
          : 'sync:${campaign.syncId.trim()}';
      final existing = seen[exactCopyKey];

      if (existing != null) {
        // Prefer the network-identified row or the more recently updated row.
        final preferCurrent = existing.syncId.isEmpty ||
            (campaign.syncId.isNotEmpty &&
                campaign.updatedAt.isAfter(existing.updatedAt));
        if (preferCurrent) {
          final index = result.indexOf(existing);
          if (index != -1) result[index] = campaign;
          seen[exactCopyKey] = campaign;
        }
        continue;
      }

      // Also suppress impossible duplicate sync identities defensively for
      // databases repaired from older pre-v0.5 schemas.
      if (seen.containsKey(syncKey)) continue;
      seen[exactCopyKey] = campaign;
      seen[syncKey] = campaign;
      result.add(campaign);
    }
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  Future<void> _rebuildCategories() async {
    _ownedCampaigns = [];
    _joinedCampaigns = [];
    if (localClientId.isEmpty) {
      _playerLinkedCharacterIds = <int>{};
      return;
    }

    for (final campaign in _campaigns) {
      final member = campaign.id == null
          ? null
          : await _service.getMemberForClient(campaignId: campaign.id!, clientId: localClientId);
      if (member?.role == CampaignRole.gm) {
        _ownedCampaigns.add(campaign);
      } else if (member?.role == CampaignRole.player) {
        _joinedCampaigns.add(campaign);
      }
    }

    _playerLinkedCharacterIds =
        await _service.getPlayerLinkedCharacterIdsForGm(localClientId);
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
    final id = await _service.createCampaign(name: name, description: description, gmName: gmName, clientId: localClientId);
    await loadCampaigns();
    final campaign = _campaigns.firstWhere((c) => c.id == id);
    await selectCampaign(campaign);
    await _publishSelectedSnapshot();
  }

  Future<void> saveCampaign({required String name, required String description}) async {
    final campaign = _selected;
    if (campaign == null) return;
    final updated = campaign.copyWith(name: name, description: description);
    await _service.updateCampaign(updated);
    await loadCampaigns();
    await _reloadMembers();
    await _publishSelectedSnapshot();
  }

  Future<void> deleteSelected() async {
    final campaign = _selected;
    final id = campaign?.id;
    if (id == null) return;
    await _service.deleteCampaign(id);
    if (campaign != null) await _syncService?.publishDelete('campaign', campaign.syncId);
    clearSelection();
    await loadCampaigns();
  }

  Future<void> addPlayer(String name) async {
    final id = _selected?.id;
    if (id == null) return;
    await _service.addPlayer(campaignId: id, name: name);
    await _reloadMembers();
    await _publishSelectedSnapshot();
  }

  Future<void> saveMember(CampaignMemberModel member) async {
    await _service.updateMember(member);
    await _reloadMembers();
    await _publishSelectedSnapshot();
  }

  Future<void> replaceGm(int memberId) async {
    final id = _selected?.id;
    if (id == null) return;
    await _service.replaceGm(campaignId: id, newGmMemberId: memberId);
    await _reloadMembers();
    await _publishSelectedSnapshot();
  }

  Future<void> removeMember(CampaignMemberModel member) async {
    await _service.removeMember(member);
    await _reloadMembers();
    await _syncService?.publishDelete('campaign_member', member.syncId);
    await _publishSelectedSnapshot();
  }

  Future<void> unlinkOwnCharacter() async {
    final campaign = _selected;
    final member = currentMembership;
    if (campaign?.id == null || member == null || member.role != CampaignRole.player) {
      throw StateError('Нет подключённого игрока для отвязки персонажа.');
    }
    if (member.linkedCharacterId == null) {
      return;
    }

    if (_syncService?.connected == true) {
      await _syncService!.unlinkOwnCharacter(member: member);
    } else {
      throw StateError('Для отвязки персонажа требуется подключение к LAN-кампании.');
    }

    await _reloadMembers();
  }

  Future<void> leaveCurrentCampaign() async {
    final campaign = _selected;
    final member = currentMembership;
    if (campaign?.id == null || member == null || member.role != CampaignRole.player) {
      throw StateError('Нет подключённого игрока для выхода из кампании.');
    }

    // Leaving is a local membership operation. A live LAN connection is only
    // needed to notify the GM immediately; when offline we still remove the
    // local membership and let the network disconnect/reconnect lifecycle
    // handle the server side asynchronously.
    if (_syncService?.connected == true) {
      try {
        await _syncService!.leaveCampaign(member: member);
      } catch (_) {
        // The player can still leave locally if the LAN connection disappeared
        // while the leave request was being sent or acknowledged.
      }
    }

    await _service.removeMember(member);
    clearSelection();
    await loadCampaigns();
  }

  Future<List<Map<String, dynamic>>> membershipsForCharacter(int characterId) => _service.getMembershipsForCharacter(characterId);

  Future<void> linkCharacter(CampaignMemberModel member, int? characterId) async {
    await _service.linkCharacter(memberId: member.id!, characterId: characterId);
    await _reloadMembers();
    await _publishSelectedSnapshot();
  }

  Future<void> _publishSelectedSnapshot() async {
    final campaign = _selected;
    if (campaign == null || campaign.syncId.isEmpty) return;
    await _syncService?.publishCampaignSnapshot(campaign.syncId);
  }

  Future<void> _reloadMembers() async {
    final id = _selected?.id;
    if (id == null) return;
    _members = await _service.getMembers(id);
    if (_selected != null) {
      _selected = await _service.getById(id) ?? _selected;
    }
    _playerLinkedCharacterIds =
        await _service.getPlayerLinkedCharacterIdsForGm(localClientId);
    notifyListeners();
  }

  Future<void> _onSyncEvent(NetworkMessage event) async {
    final entity = event.payload['entity']?.toString();
    final name = event.payload['event']?.toString();
    if (name == 'player.joined' && _connectionManager?.role == 'gm') {
      final clientId = event.payload['client_id']?.toString() ?? '';
      final displayName = event.payload['display_name']?.toString() ?? 'Игрок';
      if (clientId.isNotEmpty && _selected?.id != null && clientId != localClientId) {
        await _service.addNetworkPlayer(campaignId: _selected!.id!, clientId: clientId, name: displayName);
        await _reloadMembers();
        await _publishSelectedSnapshot();
      }
    }

    if (name == 'state.snapshot' ||
        entity == 'campaign' ||
        entity == 'campaign_member' ||
        entity == 'session' ||
        entity == 'character' ||
        name == 'player.joined' ||
        name == 'player.left') {
      await loadCampaigns();
      final selected = _selected;
      if (selected?.id != null) await _reloadMembers();
    }
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }
}
