class SessionRewardModel {
  final int? id;
  final String syncId;
  final int sessionId;
  final String characterSyncId;
  final String type;
  final int amount;
  final String reason;
  final int levelBefore;
  final int levelAfter;
  final DateTime createdAt;
  final String createdBy;

  const SessionRewardModel({
    this.id,
    this.syncId = '',
    required this.sessionId,
    required this.characterSyncId,
    this.type = 'xp',
    required this.amount,
    this.reason = '',
    this.levelBefore = 1,
    this.levelAfter = 1,
    required this.createdAt,
    this.createdBy = '',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'session_id': sessionId,
        'character_sync_id': characterSyncId,
        'type': type,
        'amount': amount,
        'reason': reason,
        'level_before': levelBefore,
        'level_after': levelAfter,
        'created_at': createdAt.toUtc().toIso8601String(),
        'created_by': createdBy,
      };

  factory SessionRewardModel.fromMap(Map<String, dynamic> map) => SessionRewardModel(
        id: map['id'] as int?,
        syncId: map['sync_id']?.toString() ?? '',
        sessionId: map['session_id'] as int,
        characterSyncId: map['character_sync_id']?.toString() ?? '',
        type: map['type']?.toString() ?? 'xp',
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        reason: map['reason']?.toString() ?? '',
        levelBefore: (map['level_before'] as num?)?.toInt() ?? 1,
        levelAfter: (map['level_after'] as num?)?.toInt() ?? 1,
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        createdBy: map['created_by']?.toString() ?? '',
      );
}
