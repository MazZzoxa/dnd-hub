enum BattleTurnStatus { active, completed }

extension BattleTurnStatusX on BattleTurnStatus {
  String get dbValue => switch (this) {
        BattleTurnStatus.active => 'active',
        BattleTurnStatus.completed => 'completed',
      };

  static BattleTurnStatus fromDb(String? value) =>
      value == 'completed' ? BattleTurnStatus.completed : BattleTurnStatus.active;
}

class BattleTurnModel {
  final int? id;
  final String syncId;
  final String battleSyncId;
  final String characterSyncId;
  final int sequence;
  final BattleTurnStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;

  const BattleTurnModel({
    this.id,
    this.syncId = '',
    required this.battleSyncId,
    required this.characterSyncId,
    required this.sequence,
    this.status = BattleTurnStatus.active,
    required this.startedAt,
    this.endedAt,
  });

  BattleTurnModel copyWith({
    int? id,
    String? syncId,
    String? battleSyncId,
    String? characterSyncId,
    int? sequence,
    BattleTurnStatus? status,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
  }) {
    return BattleTurnModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      battleSyncId: battleSyncId ?? this.battleSyncId,
      characterSyncId: characterSyncId ?? this.characterSyncId,
      sequence: sequence ?? this.sequence,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'battle_sync_id': battleSyncId,
        'character_sync_id': characterSyncId,
        'sequence': sequence,
        'status': status.dbValue,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
      };

  factory BattleTurnModel.fromMap(Map<String, dynamic> map) => BattleTurnModel(
        id: map['id'] as int?,
        syncId: map['sync_id']?.toString() ?? '',
        battleSyncId: map['battle_sync_id']?.toString() ?? '',
        characterSyncId: map['character_sync_id']?.toString() ?? '',
        sequence: (map['sequence'] as num?)?.toInt() ?? 0,
        status: BattleTurnStatusX.fromDb(map['status']?.toString()),
        startedAt: DateTime.tryParse(map['started_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        endedAt: DateTime.tryParse(map['ended_at']?.toString() ?? '')?.toLocal(),
      );
}
