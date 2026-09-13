import 'dart:convert';

/// Тип объекта библиотеки (см. docs/D&D Hub.md, п.20 и п.68).
///
/// LocalLibrary хранит объекты разных категорий в одной таблице
/// `library_items`, различая их полем `type`.
enum LibraryItemType {
  item,
  spell,
  ability,
  other;

  String get dbValue => name.toUpperCase();

  static LibraryItemType fromDbValue(String value) {
    return LibraryItemType.values.firstWhere(
      (t) => t.dbValue == value,
      orElse: () => LibraryItemType.other,
    );
  }
}

/// Происхождение объекта библиотеки (см. docs/D&D Hub.md, п.22).
enum LibrarySourceType {
  /// Создан пользователем вручную.
  userCreated,

  /// Получен через Import Manager (PDF / URL / JSON).
  imported,

  /// Часть локального набора данных приложения (заготовки, homebrew и т.д.).
  local;

  String get dbValue {
    switch (this) {
      case LibrarySourceType.userCreated:
        return 'USER_CREATED';
      case LibrarySourceType.imported:
        return 'IMPORTED';
      case LibrarySourceType.local:
        return 'LOCAL';
    }
  }

  static LibrarySourceType fromDbValue(String value) {
    switch (value) {
      case 'IMPORTED':
        return LibrarySourceType.imported;
      case 'LOCAL':
        return LibrarySourceType.local;
      case 'USER_CREATED':
      default:
        return LibrarySourceType.userCreated;
    }
  }
}

/// Объект пользовательской библиотеки контента D&D Hub — `ContentItem`
/// из docs/D&D Hub.md, п.22 и п.68.
///
/// В отличие от ItemModel/SpellModel/AbilityModel (которые привязаны к
/// конкретному character_id и описывают состояние персонажа), LibraryItem
/// не принадлежит персонажу — это переиспользуемый источник данных.
/// Поле [data] хранит специфичные для типа поля (урон оружия, школа
/// заклинания и т.д.) в виде произвольной JSON-структуры, чтобы не заводить
/// отдельную таблицу на каждый тип контента (см. п.22 ТЗ).
class LibraryItemModel {
  final int? id;
  final LibraryItemType type;
  final String name;
  final Map<String, dynamic> data;
  final LibrarySourceType sourceType;
  final String sourceUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LibraryItemModel({
    this.id,
    required this.type,
    required this.name,
    this.data = const {},
    this.sourceType = LibrarySourceType.userCreated,
    this.sourceUrl = '',
    required this.createdAt,
    required this.updatedAt,
  });

  LibraryItemModel copyWith({
    int? id,
    LibraryItemType? type,
    String? name,
    Map<String, dynamic>? data,
    LibrarySourceType? sourceType,
    String? sourceUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LibraryItemModel(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      data: data ?? this.data,
      sourceType: sourceType ?? this.sourceType,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type.dbValue,
      'name': name,
      'data': jsonEncode(data),
      'source_type': sourceType.dbValue,
      'source_url': sourceUrl,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static Map<String, dynamic> _decodeData(dynamic raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  factory LibraryItemModel.fromMap(Map<String, dynamic> map) {
    return LibraryItemModel(
      id: map['id'] as int?,
      type: LibraryItemType.fromDbValue(map['type'] as String? ?? ''),
      name: map['name'] as String? ?? '',
      data: _decodeData(map['data']),
      sourceType: LibrarySourceType.fromDbValue(map['source_type'] as String? ?? ''),
      sourceUrl: map['source_url'] as String? ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
