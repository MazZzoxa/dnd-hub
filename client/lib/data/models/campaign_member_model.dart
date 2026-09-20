enum CampaignRole { gm, player }

extension CampaignRoleX on CampaignRole {
  String get dbValue => this == CampaignRole.gm ? 'gm' : 'player';
  String get label => this == CampaignRole.gm ? 'GM' : 'Player';
  static CampaignRole fromDb(String? value) => value == 'gm' ? CampaignRole.gm : CampaignRole.player;
}

class CampaignMemberModel {
  final int? id;
  final String syncId;
  final int campaignId;
  final String name;
  final CampaignRole role;
  final String clientId;
  final int? linkedCharacterId;
  final DateTime createdAt;

  const CampaignMemberModel({
    this.id,
    this.syncId = '',
    required this.campaignId,
    required this.name,
    this.role = CampaignRole.player,
    this.clientId = '',
    this.linkedCharacterId,
    required this.createdAt,
  });

  CampaignMemberModel copyWith({
    String? syncId,
    int? id,
    int? campaignId,
    String? name,
    CampaignRole? role,
    String? clientId,
    int? linkedCharacterId,
    bool clearLinkedCharacterId = false,
    DateTime? createdAt,
  }) => CampaignMemberModel(
        id: id ?? this.id,
      syncId: syncId ?? this.syncId,
        campaignId: campaignId ?? this.campaignId,
        name: name ?? this.name,
        role: role ?? this.role,
        clientId: clientId ?? this.clientId,
        linkedCharacterId: clearLinkedCharacterId ? null : (linkedCharacterId ?? this.linkedCharacterId),
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
      'sync_id': syncId,
        'campaign_id': campaignId,
        'name': name,
        'role': role.dbValue,
        'client_id': clientId,
        'linked_character_id': linkedCharacterId,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory CampaignMemberModel.fromMap(Map<String, dynamic> map) => CampaignMemberModel(
        id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
        campaignId: map['campaign_id'] as int,
        name: map['name'] as String? ?? '',
        role: CampaignRoleX.fromDb(map['role']?.toString()),
        clientId: map['client_id']?.toString() ?? '',
        linkedCharacterId: map['linked_character_id'] as int?,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
