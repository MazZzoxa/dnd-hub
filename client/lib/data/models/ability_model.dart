class AbilityModel {
  final int? id;
  final int characterId;
  final String name;
  final String description;
  final String source; // класс / раса / талант / другое
  final int sortOrder;

  /// Ссылка на объект Local Content Library (см. docs/D&D Hub.md п.34),
  /// из которого была добавлена эта способность. null — создана вручную.
  final int? libraryItemId;

  /// Ссылка на источник (правило/книга/страница), необязательное поле.
  /// Не путать с [source] — тот хранит происхождение (класс/раса/талант).
  final String sourceUrl;

  const AbilityModel({
    this.id,
    required this.characterId,
    required this.name,
    this.description = '',
    this.source = '',
    this.sortOrder = 0,
    this.libraryItemId,
    this.sourceUrl = '',
  });

  AbilityModel copyWith({
    int? id,
    int? characterId,
    String? name,
    String? description,
    String? source,
    int? sortOrder,
    int? libraryItemId,
    String? sourceUrl,
  }) {
    return AbilityModel(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      description: description ?? this.description,
      source: source ?? this.source,
      sortOrder: sortOrder ?? this.sortOrder,
      libraryItemId: libraryItemId ?? this.libraryItemId,
      sourceUrl: sourceUrl ?? this.sourceUrl,
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
      'library_item_id': libraryItemId,
      'source_url': sourceUrl,
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
      libraryItemId: map['library_item_id'] as int?,
      sourceUrl: map['source_url'] as String? ?? '',
    );
  }
}
