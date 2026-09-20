/// Строка таблицы "Атаки и заклинания": название / бонус атаки / урон.
/// Бонус атаки и урон хранятся текстом (напр. "+10", "1к8 +10"),
/// так как в D&D это не всегда чистое число (могут быть кости, "—" и т.д.).
class AttackModel {
  final int? id;
  final String syncId;
  final int characterId;
  final String name;
  final String attackBonus;
  final String damage;
  final int sortOrder;

  const AttackModel({
    this.id,
    this.syncId = '',
    required this.characterId,
    required this.name,
    this.attackBonus = '',
    this.damage = '',
    this.sortOrder = 0,
  });

  AttackModel copyWith({
    String? syncId,
    int? id,
    int? characterId,
    String? name,
    String? attackBonus,
    String? damage,
    int? sortOrder,
  }) {
    return AttackModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      attackBonus: attackBonus ?? this.attackBonus,
      damage: damage ?? this.damage,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sync_id': syncId,
      'character_id': characterId,
      'name': name,
      'attack_bonus': attackBonus,
      'damage': damage,
      'sort_order': sortOrder,
    };
  }

  factory AttackModel.fromMap(Map<String, dynamic> map) {
    return AttackModel(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
      characterId: map['character_id'] as int,
      name: map['name'] as String? ?? '',
      attackBonus: map['attack_bonus'] as String? ?? '',
      damage: map['damage'] as String? ?? '',
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}
