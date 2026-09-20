enum SessionStatus { planned, active, completed }

extension SessionStatusX on SessionStatus {
  String get dbValue => switch (this) {
        SessionStatus.planned => 'planned',
        SessionStatus.active => 'active',
        SessionStatus.completed => 'completed',
      };

  String get label => switch (this) {
        SessionStatus.planned => 'Запланирована',
        SessionStatus.active => 'Активна',
        SessionStatus.completed => 'Завершена',
      };

  static SessionStatus fromDb(String? value) => switch (value) {
        'active' => SessionStatus.active,
        'completed' => SessionStatus.completed,
        _ => SessionStatus.planned,
      };
}

class SessionModel {
  final int? id;
  final String syncId;
  final int campaignId;
  final String title;
  final String notes;
  final SessionStatus status;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final DateTime updatedAt;

  const SessionModel({
    this.id,
    this.syncId = '',
    required this.campaignId,
    required this.title,
    this.notes = '',
    this.status = SessionStatus.planned,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    required this.updatedAt,
  });

  SessionModel copyWith({
    String? syncId,
    int? id,
    int? campaignId,
    String? title,
    String? notes,
    SessionStatus? status,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearStartedAt = false,
    bool clearEndedAt = false,
    DateTime? updatedAt,
  }) {
    return SessionModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      campaignId: campaignId ?? this.campaignId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
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
        'title': title,
        'notes': notes,
        'status': status.dbValue,
        'created_at': createdAt.toUtc().toIso8601String(),
        'started_at': startedAt?.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory SessionModel.fromMap(Map<String, dynamic> map) => SessionModel(
        id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
        campaignId: map['campaign_id'] as int,
        title: map['title'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
        status: SessionStatusX.fromDb(map['status']?.toString()),
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        startedAt: DateTime.tryParse(map['started_at']?.toString() ?? '')?.toLocal(),
        endedAt: DateTime.tryParse(map['ended_at']?.toString() ?? '')?.toLocal(),
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
