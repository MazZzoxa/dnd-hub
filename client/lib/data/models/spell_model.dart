class SpellModel {
  final int? id;
  final String syncId;
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

  /// Ссылка на объект Local Content Library (см. docs/D&D Hub.md п.34),
  /// из которого было добавлено это заклинание. null — создано вручную.
  final int? libraryItemId;

  /// Ссылка на источник (правило/книга/страница), необязательное поле.
  final String sourceUrl;

  const SpellModel({
    this.id,
    this.syncId = '',
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
    this.libraryItemId,
    this.sourceUrl = '',
  });

  SpellModel copyWith({
    String? syncId,
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
    int? libraryItemId,
    String? sourceUrl,
  }) {
    return SpellModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
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
      libraryItemId: libraryItemId ?? this.libraryItemId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sync_id': syncId,
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
      'library_item_id': libraryItemId,
      'source_url': sourceUrl,
    };
  }

  factory SpellModel.fromMap(Map<String, dynamic> map) {
    return SpellModel(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
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
      libraryItemId: map['library_item_id'] as int?,
      sourceUrl: map['source_url'] as String? ?? '',
    );
  }
}
