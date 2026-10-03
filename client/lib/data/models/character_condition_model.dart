import 'dart:convert';

class CharacterConditionModel {
  final int? id;
  final String syncId;
  final int characterId;
  final String characterSyncId;
  final String name;
  final String description;
  final String sourceCharacterSyncId;
  final String sourceLabel;
  final int durationRounds;
  final int remainingRounds;
  final String scope;
  final bool active;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CharacterConditionModel({
    this.id,
    this.syncId = '',
    required this.characterId,
    required this.characterSyncId,
    required this.name,
    this.description = '',
    this.sourceCharacterSyncId = '',
    this.sourceLabel = '',
    this.durationRounds = 0,
    this.remainingRounds = 0,
    this.scope = 'character',
    this.active = true,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  CharacterConditionModel copyWith({
    int? id, String? syncId, int? characterId, String? characterSyncId, String? name,
    String? description, String? sourceCharacterSyncId, String? sourceLabel,
    int? durationRounds, int? remainingRounds, String? scope, bool? active,
    Map<String, dynamic>? metadata, DateTime? createdAt, DateTime? updatedAt,
  }) => CharacterConditionModel(
    id: id ?? this.id, syncId: syncId ?? this.syncId, characterId: characterId ?? this.characterId,
    characterSyncId: characterSyncId ?? this.characterSyncId, name: name ?? this.name,
    description: description ?? this.description, sourceCharacterSyncId: sourceCharacterSyncId ?? this.sourceCharacterSyncId,
    sourceLabel: sourceLabel ?? this.sourceLabel, durationRounds: durationRounds ?? this.durationRounds,
    remainingRounds: remainingRounds ?? this.remainingRounds, scope: scope ?? this.scope, active: active ?? this.active,
    metadata: metadata ?? this.metadata, createdAt: createdAt ?? this.createdAt, updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'sync_id': syncId,
    'character_id': characterId,
    'character_sync_id': characterSyncId,
    'name': name,
    'description': description,
    'source_character_sync_id': sourceCharacterSyncId,
    'source_label': sourceLabel,
    'duration_rounds': durationRounds,
    'remaining_rounds': remainingRounds,
    'scope': scope,
    'active': active ? 1 : 0,
    'metadata': jsonEncode(metadata),
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  factory CharacterConditionModel.fromMap(Map<String, dynamic> map) {
    final raw = map['metadata'];
    Map<String, dynamic> metadata = const {};
    if (raw is Map) {
      metadata = raw.map((k, v) => MapEntry(k.toString(), v));
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) metadata = decoded.map((k, v) => MapEntry(k.toString(), v));
      } catch (_) {}
    }
    return CharacterConditionModel(
      id: map['id'] as int?, syncId: map['sync_id']?.toString() ?? '',
      characterId: (map['character_id'] as num?)?.toInt() ?? 0,
      characterSyncId: map['character_sync_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '', description: map['description']?.toString() ?? '',
      sourceCharacterSyncId: map['source_character_sync_id']?.toString() ?? '',
      sourceLabel: map['source_label']?.toString() ?? '',
      durationRounds: (map['duration_rounds'] as num?)?.toInt() ?? 0,
      remainingRounds: (map['remaining_rounds'] as num?)?.toInt() ?? 0,
      scope: map['scope']?.toString() ?? 'character',
      active: (map['active'] is bool) ? map['active'] as bool : ((map['active'] as num?)?.toInt() ?? 1) == 1,
      metadata: metadata,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}
