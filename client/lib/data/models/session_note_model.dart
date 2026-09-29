class SessionNoteModel {
  final int? id;
  final String syncId;
  final int sessionId;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SessionNoteModel({
    this.id,
    this.syncId = '',
    required this.sessionId,
    required this.title,
    this.content = '',
    required this.createdAt,
    required this.updatedAt,
  });

  SessionNoteModel copyWith({
    int? id,
    String? syncId,
    int? sessionId,
    String? title,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SessionNoteModel(
        id: id ?? this.id,
        syncId: syncId ?? this.syncId,
        sessionId: sessionId ?? this.sessionId,
        title: title ?? this.title,
        content: content ?? this.content,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'session_id': sessionId,
        'title': title,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory SessionNoteModel.fromMap(Map<String, dynamic> map) => SessionNoteModel(
        id: map['id'] as int?,
        syncId: map['sync_id']?.toString() ?? '',
        sessionId: map['session_id'] as int,
        title: map['title']?.toString() ?? '',
        content: map['content']?.toString() ?? '',
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
