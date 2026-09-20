class NoteModel {
  final int? id;
  final String syncId;
  final int characterId;
  final String title;
  final String content;
  final DateTime createdAt;

  const NoteModel({
    this.id,
    this.syncId = '',
    required this.characterId,
    this.title = '',
    required this.content,
    required this.createdAt,
  });

  NoteModel copyWith({
    String? syncId,
    int? id,
    int? characterId,
    String? title,
    String? content,
    DateTime? createdAt,
  }) {
    return NoteModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      characterId: characterId ?? this.characterId,
      title: title ?? this.title,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sync_id': syncId,
      'character_id': characterId,
      'title': title,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory NoteModel.fromMap(Map<String, dynamic> map) {
    return NoteModel(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
      characterId: map['character_id'] as int,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
