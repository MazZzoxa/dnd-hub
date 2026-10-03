import '../../network/services/sync_ids.dart';

class CustomActionModel {
  final int? id;
  final String syncId;
  final int characterId;
  final String name;
  final String description;
  final String attackFormula;
  final String effectFormula;
  final String effectType;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomActionModel({
    this.id,
    this.syncId = '',
    required this.characterId,
    required this.name,
    this.description = '',
    this.attackFormula = '',
    this.effectFormula = '',
    this.effectType = 'none',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  CustomActionModel copyWith({
    int? id, String? syncId, int? characterId, String? name, String? description,
    String? attackFormula, String? effectFormula, String? effectType, int? sortOrder,
    DateTime? createdAt, DateTime? updatedAt,
  }) => CustomActionModel(
    id: id ?? this.id,
    syncId: syncId ?? this.syncId,
    characterId: characterId ?? this.characterId,
    name: name ?? this.name,
    description: description ?? this.description,
    attackFormula: attackFormula ?? this.attackFormula,
    effectFormula: effectFormula ?? this.effectFormula,
    effectType: effectType ?? this.effectType,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'sync_id': syncId,
    'character_id': characterId,
    'name': name,
    'description': description,
    'attack_formula': attackFormula,
    'effect_formula': effectFormula,
    'effect_type': effectType,
    'sort_order': sortOrder,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory CustomActionModel.fromMap(Map<String, dynamic> map) => CustomActionModel(
    id: map['id'] as int?,
    syncId: map['sync_id']?.toString() ?? '',
    characterId: (map['character_id'] as num?)?.toInt() ?? 0,
    name: map['name']?.toString() ?? '',
    description: map['description']?.toString() ?? '',
    attackFormula: map['attack_formula']?.toString() ?? '',
    effectFormula: map['effect_formula']?.toString() ?? '',
    effectType: map['effect_type']?.toString() ?? 'none',
    sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
  );

  CustomActionModel withNewSyncId() => copyWith(syncId: syncId.isEmpty ? SyncIds.newId() : syncId);
}
