class ItemModel {
  final int? id;
  final String syncId;
  final int characterId;
  final String name;
  final int quantity;
  final String category; // Weapons / Consumables / Other / ...
  final String description;
  final double weight;

  /// Ссылка на объект Local Content Library (см. docs/D&D Hub.md п.34),
  /// из которого был добавлен этот предмет. null — предмет создан вручную
  /// и не связан с библиотекой.
  final int? libraryItemId;

  /// Ссылка на источник (правило/книга/страница), необязательное поле.
  final String sourceUrl;

  const ItemModel({
    this.id,
    this.syncId = '',
    required this.characterId,
    required this.name,
    this.quantity = 1,
    this.category = 'Other',
    this.description = '',
    this.weight = 0,
    this.libraryItemId,
    this.sourceUrl = '',
  });

  ItemModel copyWith({
    String? syncId,
    int? id,
    int? characterId,
    String? name,
    int? quantity,
    String? category,
    String? description,
    double? weight,
    int? libraryItemId,
    String? sourceUrl,
  }) {
    return ItemModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
      description: description ?? this.description,
      weight: weight ?? this.weight,
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
      'quantity': quantity,
      'category': category,
      'description': description,
      'weight': weight,
      'library_item_id': libraryItemId,
      'source_url': sourceUrl,
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
      characterId: map['character_id'] as int,
      name: map['name'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 1,
      category: map['category'] as String? ?? 'Other',
      description: map['description'] as String? ?? '',
      weight: (map['weight'] as num?)?.toDouble() ?? 0,
      libraryItemId: map['library_item_id'] as int?,
      sourceUrl: map['source_url'] as String? ?? '',
    );
  }
}
