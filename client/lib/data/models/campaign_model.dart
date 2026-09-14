class CampaignModel {
  final int? id;
  final String name;
  final String description;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CampaignModel({
    this.id,
    required this.name,
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
  });

  CampaignModel copyWith({
    int? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => CampaignModel(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory CampaignModel.fromMap(Map<String, dynamic> map) => CampaignModel(
        id: map['id'] as int?,
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
        createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );
}
