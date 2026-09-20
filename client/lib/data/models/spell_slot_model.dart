/// Ячейки заклинаний конкретного уровня (1-9) для персонажа.
/// Заговоры (уровень 0) ячеек не расходуют и здесь не хранятся.
class SpellSlotModel {
  final String syncId;
  final int characterId;
  final int level; // 1..9
  final int total;
  final int used;

  const SpellSlotModel({
    this.syncId = '',
    required this.characterId,
    required this.level,
    this.total = 0,
    this.used = 0,
  });

  SpellSlotModel copyWith({String? syncId, int? total, int? used}) {
    return SpellSlotModel(
      syncId: syncId ?? this.syncId,
      characterId: characterId,
      level: level,
      total: total ?? this.total,
      used: used ?? this.used,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sync_id': syncId,
      'character_id': characterId,
      'level': level,
      'total': total,
      'used': used,
    };
  }

  factory SpellSlotModel.fromMap(Map<String, dynamic> map) {
    return SpellSlotModel(
      syncId: map['sync_id']?.toString() ?? '',
      characterId: map['character_id'] as int,
      level: map['level'] as int,
      total: map['total'] as int? ?? 0,
      used: map['used'] as int? ?? 0,
    );
  }
}
