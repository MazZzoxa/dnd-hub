class ItemModel {
  final int? id;
  final int characterId;
  final String name;
  final int quantity;
  final String category; // Weapons / Consumables / Other / ...
  final String description;
  final double weight;

  const ItemModel({
    this.id,
    required this.characterId,
    required this.name,
    this.quantity = 1,
    this.category = 'Other',
    this.description = '',
    this.weight = 0,
  });

  ItemModel copyWith({
    int? id,
    int? characterId,
    String? name,
    int? quantity,
    String? category,
    String? description,
    double? weight,
  }) {
    return ItemModel(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      category: category ?? this.category,
      description: description ?? this.description,
      weight: weight ?? this.weight,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'character_id': characterId,
      'name': name,
      'quantity': quantity,
      'category': category,
      'description': description,
      'weight': weight,
    };
  }

  factory ItemModel.fromMap(Map<String, dynamic> map) {
    return ItemModel(
      id: map['id'] as int?,
      characterId: map['character_id'] as int,
      name: map['name'] as String? ?? '',
      quantity: map['quantity'] as int? ?? 1,
      category: map['category'] as String? ?? 'Other',
      description: map['description'] as String? ?? '',
      weight: (map['weight'] as num?)?.toDouble() ?? 0,
    );
  }
}
