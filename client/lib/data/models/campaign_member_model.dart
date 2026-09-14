enum CampaignRole { gm, player }

extension CampaignRoleX on CampaignRole {
  String get dbValue => this == CampaignRole.gm ? 'gm' : 'player';
  String get label => this == CampaignRole.gm ? 'GM' : 'Player';
  static CampaignRole fromDb(String? value) => value == 'gm' ? CampaignRole.gm : CampaignRole.player;
}

class CampaignMemberModel {
  final int? id;
  final int campaignId;
  final String name;
  final CampaignRole role;
  final int? linkedCharacterId;
  final DateTime createdAt;

  const CampaignMemberModel({
    this.id,
    required this.campaignId,
    required this.name,
    this.role = CampaignRole.player,
    this.linkedCharacterId,
    required this.createdAt,
  });

  CampaignMemberModel copyWith({
    int? id,
    int? campaignId,
    String? name,
    CampaignRole? role,
    int? linkedCharacterId,
    bool clearLinkedCharacterId = false,
    DateTime? createdAt,
  }) => CampaignMemberModel(
        id: id ?? this.id,
        campaignId: campaignId ?? this.campaignId,
        name: name ?? this.name,
        role: role ?? this.role,
        linkedCharacterId: clearLinkedCharacterId ? null : (linkedCharacterId ?? this.linkedCharacterId),
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'campaign_id': campaignId,
        'name': name,
        'role': role.dbValue,
        'linked_character_id': linkedCharacterId,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory CampaignMemberModel.fromMap(Map<String, dynamic> map) => CampaignMemberModel(
        id: map['id'] as int?,
        campaignId: map['campaign_id'] as int,
        name: map['name'] as String? ?? '',
        role: CampaignRoleX.fromDb(map['role']?.toString()),
        linkedCharacterId: map['linked_character_id'] as int?,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
