class XpTransactionModel {
  final int? id;
  final int characterId;
  final int delta;
  final int xpBefore;
  final int xpAfter;
  final int levelBefore;
  final int levelAfter;
  final String reason;
  final DateTime createdAt;

  const XpTransactionModel({
    this.id,
    required this.characterId,
    required this.delta,
    required this.xpBefore,
    required this.xpAfter,
    required this.levelBefore,
    required this.levelAfter,
    required this.reason,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'character_id': characterId,
        'delta': delta,
        'xp_before': xpBefore,
        'xp_after': xpAfter,
        'level_before': levelBefore,
        'level_after': levelAfter,
        'reason': reason,
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  factory XpTransactionModel.fromMap(Map<String, dynamic> map) => XpTransactionModel(
        id: map['id'] as int?,
        characterId: map['character_id'] as int,
        delta: map['delta'] as int,
        xpBefore: map['xp_before'] as int,
        xpAfter: map['xp_after'] as int,
        levelBefore: map['level_before'] as int,
        levelAfter: map['level_after'] as int,
        reason: map['reason'] as String? ?? '',
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
