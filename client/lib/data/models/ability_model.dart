class AbilityModel {
  final int? id;
  final int characterId;
  final String name;
  final String description;
  final String source; // класс / раса / талант / другое
  final int sortOrder;

  const AbilityModel({
    this.id,
    required this.characterId,
    required this.name,
    this.description = '',
    this.source = '',
    this.sortOrder = 0,
  });

  AbilityModel copyWith({
    int? id,
    int? characterId,
    String? name,
    String? description,
    String? source,
    int? sortOrder,
  }) {
    return AbilityModel(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      description: description ?? this.description,
      source: source ?? this.source,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'character_id': characterId,
      'name': name,
      'description': description,
      'source': source,
      'sort_order': sortOrder,
    };
  }

  factory AbilityModel.fromMap(Map<String, dynamic> map) {
    return AbilityModel(
      id: map['id'] as int?,
      characterId: map['character_id'] as int,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      source: map['source'] as String? ?? '',
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }
}
