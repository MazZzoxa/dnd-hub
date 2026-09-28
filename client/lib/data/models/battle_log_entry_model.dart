import 'dart:convert';

class BattleLogEntryModel {
  final int? id;
  final String syncId;
  final String battleSyncId;
  final String type;
  final String actorCharacterSyncId;
  final String targetCharacterSyncId;
  final String targetLabel;
  final String actionSyncId;
  final String actionRequestSyncId;
  final int? amount;
  final int? turnSequence;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  const BattleLogEntryModel({
    this.id,
    this.syncId = '',
    required this.battleSyncId,
    required this.type,
    this.actorCharacterSyncId = '',
    this.targetCharacterSyncId = '',
    this.targetLabel = '',
    this.actionSyncId = '',
    this.actionRequestSyncId = '',
    this.amount,
    this.turnSequence,
    this.metadata = const {},
    required this.createdAt,
  });

  BattleLogEntryModel copyWith({
    int? id,
    String? syncId,
    String? battleSyncId,
    String? type,
    String? actorCharacterSyncId,
    String? targetCharacterSyncId,
    String? targetLabel,
    String? actionSyncId,
    String? actionRequestSyncId,
    int? amount,
    bool clearAmount = false,
    int? turnSequence,
    bool clearTurnSequence = false,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) => BattleLogEntryModel(
        id: id ?? this.id,
        syncId: syncId ?? this.syncId,
        battleSyncId: battleSyncId ?? this.battleSyncId,
        type: type ?? this.type,
        actorCharacterSyncId: actorCharacterSyncId ?? this.actorCharacterSyncId,
        targetCharacterSyncId: targetCharacterSyncId ?? this.targetCharacterSyncId,
        targetLabel: targetLabel ?? this.targetLabel,
        actionSyncId: actionSyncId ?? this.actionSyncId,
        actionRequestSyncId: actionRequestSyncId ?? this.actionRequestSyncId,
        amount: clearAmount ? null : (amount ?? this.amount),
        turnSequence: clearTurnSequence ? null : (turnSequence ?? this.turnSequence),
        metadata: metadata ?? this.metadata,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'battle_sync_id': battleSyncId,
        'type': type,
        'actor_character_sync_id': actorCharacterSyncId,
        'target_character_sync_id': targetCharacterSyncId,
        'target_label': targetLabel,
        'action_sync_id': actionSyncId,
        'action_request_sync_id': actionRequestSyncId,
        'amount': amount,
        'turn_sequence': turnSequence,
        'metadata': jsonEncode(metadata),
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory BattleLogEntryModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> metadata = const {};
    final raw = map['metadata'];
    if (raw is Map) {
      metadata = raw.map((key, value) => MapEntry(key.toString(), value));
    } else if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          metadata = decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }

    return BattleLogEntryModel(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
      battleSyncId: map['battle_sync_id']?.toString() ?? '',
      type: map['type']?.toString() ?? '',
      actorCharacterSyncId: map['actor_character_sync_id']?.toString() ?? '',
      targetCharacterSyncId: map['target_character_sync_id']?.toString() ?? '',
      targetLabel: map['target_label']?.toString() ?? '',
      actionSyncId: map['action_sync_id']?.toString() ?? '',
      actionRequestSyncId: map['action_request_sync_id']?.toString() ?? '',
      amount: (map['amount'] as num?)?.toInt(),
      turnSequence: (map['turn_sequence'] as num?)?.toInt(),
      metadata: metadata,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}
