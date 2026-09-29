import 'dart:convert';

class SessionEventModel {
  final int? id;
  final String syncId;
  final int sessionId;
  final String type;
  final String title;
  final String description;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final String createdBy;

  const SessionEventModel({
    this.id,
    this.syncId = '',
    required this.sessionId,
    required this.type,
    required this.title,
    this.description = '',
    this.metadata = const {},
    required this.createdAt,
    this.createdBy = '',
  });

  SessionEventModel copyWith({
    int? id,
    String? syncId,
    int? sessionId,
    String? type,
    String? title,
    String? description,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    String? createdBy,
  }) => SessionEventModel(
        id: id ?? this.id,
        syncId: syncId ?? this.syncId,
        sessionId: sessionId ?? this.sessionId,
        type: type ?? this.type,
        title: title ?? this.title,
        description: description ?? this.description,
        metadata: metadata ?? this.metadata,
        createdAt: createdAt ?? this.createdAt,
        createdBy: createdBy ?? this.createdBy,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'session_id': sessionId,
        'type': type,
        'title': title,
        'description': description,
        'metadata': jsonEncode(metadata),
        'created_at': createdAt.toUtc().toIso8601String(),
        'created_by': createdBy,
      };

  factory SessionEventModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> metadata = const {};
    final raw = map['metadata'];
    if (raw is Map) {
      metadata = raw.map((key, value) => MapEntry(key.toString(), value));
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          metadata = decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return SessionEventModel(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
      sessionId: map['session_id'] as int,
      type: map['type']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      metadata: metadata,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      createdBy: map['created_by']?.toString() ?? '',
    );
  }
}
