class SessionLootModel {
  final int? id;
  final String syncId;
  final int sessionId;
  final String name;
  final String description;
  final int quantity;
  final String source;
  final String status;
  final String? claimedByCharacterSyncId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionLootModel({
    this.id,
    this.syncId = '',
    required this.sessionId,
    required this.name,
    this.description = '',
    this.quantity = 1,
    this.source = '',
    this.status = 'available',
    this.claimedByCharacterSyncId,
    required this.createdAt,
    required this.updatedAt,
  });

  SessionLootModel copyWith({
    int? id,
    String? syncId,
    int? sessionId,
    String? name,
    String? description,
    int? quantity,
    String? source,
    String? status,
    String? claimedByCharacterSyncId,
    bool clearClaimedBy = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SessionLootModel(
        id: id ?? this.id,
        syncId: syncId ?? this.syncId,
        sessionId: sessionId ?? this.sessionId,
        name: name ?? this.name,
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        source: source ?? this.source,
        status: status ?? this.status,
        claimedByCharacterSyncId: clearClaimedBy
            ? null
            : (claimedByCharacterSyncId ?? this.claimedByCharacterSyncId),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'session_id': sessionId,
        'name': name,
        'description': description,
        'quantity': quantity,
        'source': source,
        'status': status,
        'claimed_by_character_sync_id': claimedByCharacterSyncId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory SessionLootModel.fromMap(Map<String, dynamic> map) => SessionLootModel(
        id: map['id'] as int?,
        syncId: map['sync_id']?.toString() ?? '',
        sessionId: map['session_id'] as int,
        name: map['name']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        quantity: (map['quantity'] as num?)?.toInt() ?? 1,
        source: map['source']?.toString() ?? '',
        status: map['status']?.toString() ?? 'available',
        claimedByCharacterSyncId: map['claimed_by_character_sync_id']?.toString(),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
