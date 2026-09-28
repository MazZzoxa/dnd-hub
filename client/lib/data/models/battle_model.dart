enum BattleStatus { active, completed }

extension BattleStatusX on BattleStatus {
  String get dbValue => switch (this) {
        BattleStatus.active => 'active',
        BattleStatus.completed => 'completed',
      };

  String get label => switch (this) {
        BattleStatus.active => 'Активен',
        BattleStatus.completed => 'Завершён',
      };

  static BattleStatus fromDb(String? value) =>
      value == 'completed' ? BattleStatus.completed : BattleStatus.active;
}

class BattleModel {
  final int? id;
  final String syncId;
  final int campaignId;
  final int sessionId;
  final BattleStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime updatedAt;

  const BattleModel({
    this.id,
    this.syncId = '',
    required this.campaignId,
    required this.sessionId,
    this.status = BattleStatus.active,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    required this.updatedAt,
  });

  BattleModel copyWith({
    int? id,
    String? syncId,
    int? campaignId,
    int? sessionId,
    BattleStatus? status,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearStartedAt = false,
    bool clearEndedAt = false,
    DateTime? updatedAt,
  }) {
    return BattleModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      campaignId: campaignId ?? this.campaignId,
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'campaign_id': campaignId,
        'session_id': sessionId,
        'status': status.dbValue,
        'created_at': createdAt.toUtc().toIso8601String(),
        'started_at': startedAt?.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory BattleModel.fromMap(Map<String, dynamic> map) => BattleModel(
        id: map['id'] as int?,
        syncId: map['sync_id']?.toString() ?? '',
        campaignId: map['campaign_id'] as int,
        sessionId: map['session_id'] as int,
        status: BattleStatusX.fromDb(map['status']?.toString()),
        createdAt: DateTime.tryParse(
              map['created_at']?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now(),
        startedAt:
            DateTime.tryParse(map['started_at']?.toString() ?? '')?.toLocal(),
        endedAt:
            DateTime.tryParse(map['ended_at']?.toString() ?? '')?.toLocal(),
        updatedAt: DateTime.tryParse(
              map['updated_at']?.toString() ?? '',
            )?.toLocal() ??
            DateTime.now(),
      );
}
