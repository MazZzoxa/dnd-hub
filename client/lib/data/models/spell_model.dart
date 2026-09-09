class SpellModel {
  final int? id;
  final int characterId;
  final String name;
  final int level; // 0 = заговор (cantrip)
  final String type; // школа магии
  final String range;
  final String components;
  final String castingTime; // действие / бонусное действие / реакция / время
  final String duration;
  final String description;
  final bool prepared;

  const SpellModel({
    this.id,
    required this.characterId,
    required this.name,
    this.level = 0,
    this.type = '',
    this.range = '',
    this.components = '',
    this.castingTime = '',
    this.duration = '',
    this.description = '',
    this.prepared = false,
  });

  SpellModel copyWith({
    int? id,
    int? characterId,
    String? name,
    int? level,
    String? type,
    String? range,
    String? components,
    String? castingTime,
    String? duration,
    String? description,
    bool? prepared,
  }) {
    return SpellModel(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      level: level ?? this.level,
      type: type ?? this.type,
      range: range ?? this.range,
      components: components ?? this.components,
      castingTime: castingTime ?? this.castingTime,
      duration: duration ?? this.duration,
      description: description ?? this.description,
      prepared: prepared ?? this.prepared,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'character_id': characterId,
      'name': name,
      'level': level,
      'type': type,
      'range': range,
      'components': components,
      'casting_time': castingTime,
      'duration': duration,
      'description': description,
      'prepared': prepared ? 1 : 0,
    };
  }

  factory SpellModel.fromMap(Map<String, dynamic> map) {
    return SpellModel(
      id: map['id'] as int?,
      characterId: map['character_id'] as int,
      name: map['name'] as String? ?? '',
      level: map['level'] as int? ?? 0,
      type: map['type'] as String? ?? '',
      range: map['range'] as String? ?? '',
      components: map['components'] as String? ?? '',
      castingTime: map['casting_time'] as String? ?? '',
      duration: map['duration'] as String? ?? '',
      description: map['description'] as String? ?? '',
      prepared: (map['prepared'] as int? ?? 0) == 1,
    );
  }
}
