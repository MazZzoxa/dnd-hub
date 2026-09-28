class BattleProjectionModel {
  final String characterSyncId;
  final String name;
  final int hp;
  final int maxHp;
  final int temporaryHp;
  final int armorClass;
  final int initiative;
  final String playerClientId;

  const BattleProjectionModel({
    required this.characterSyncId,
    required this.name,
    required this.hp,
    required this.maxHp,
    required this.temporaryHp,
    required this.armorClass,
    this.initiative = 0,
    this.playerClientId = '',
  });

  bool isOwn(String clientId) =>
      playerClientId.isNotEmpty && playerClientId == clientId;

  factory BattleProjectionModel.fromMap(Map<String, dynamic> map) =>
      BattleProjectionModel(
        characterSyncId: map['character_sync_id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Character',
        hp: (map['hp'] as num?)?.toInt() ?? 0,
        maxHp: (map['max_hp'] as num?)?.toInt() ?? 0,
        temporaryHp: (map['temporary_hp'] as num?)?.toInt() ?? 0,
        armorClass: (map['armor_class'] as num?)?.toInt() ?? 0,
        initiative: (map['initiative'] as num?)?.toInt() ?? 0,
        playerClientId: map['player_client_id']?.toString() ?? '',
      );
}
