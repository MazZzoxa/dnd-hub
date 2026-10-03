import 'dart:convert';

enum BattleActionRequestStatus { declared, pendingGm, approved, modified, rejected }

enum BattleTargetType { self, ally, external }

enum BattleActionType { attack, spell, ability, item, manual }

enum BattleEffectType { none, damage, healing, temporaryHp, conditionApply, conditionRemove }

extension BattleActionRequestStatusX on BattleActionRequestStatus {
  String get dbValue => switch (this) {
        BattleActionRequestStatus.declared => 'declared',
        BattleActionRequestStatus.pendingGm => 'pending_gm',
        BattleActionRequestStatus.approved => 'approved',
        BattleActionRequestStatus.modified => 'modified',
        BattleActionRequestStatus.rejected => 'rejected',
      };

  static BattleActionRequestStatus fromDb(String? value) => switch (value) {
        'declared' => BattleActionRequestStatus.declared,
        'approved' => BattleActionRequestStatus.approved,
        'modified' => BattleActionRequestStatus.modified,
        'rejected' => BattleActionRequestStatus.rejected,
        _ => BattleActionRequestStatus.pendingGm,
      };
}

extension BattleTargetTypeX on BattleTargetType {
  String get dbValue => switch (this) {
        BattleTargetType.self => 'self',
        BattleTargetType.ally => 'ally',
        BattleTargetType.external => 'external',
      };
  static BattleTargetType fromDb(String? value) => switch (value) {
        'ally' => BattleTargetType.ally,
        'external' => BattleTargetType.external,
        _ => BattleTargetType.self,
      };
}

extension BattleActionTypeX on BattleActionType {
  String get dbValue => switch (this) {
        BattleActionType.attack => 'attack',
        BattleActionType.spell => 'spell',
        BattleActionType.ability => 'ability',
        BattleActionType.item => 'item',
        BattleActionType.manual => 'manual',
      };
  static BattleActionType fromDb(String? value) => switch (value) {
        'spell' => BattleActionType.spell,
        'ability' => BattleActionType.ability,
        'item' => BattleActionType.item,
        'manual' => BattleActionType.manual,
        _ => BattleActionType.attack,
      };
}

extension BattleEffectTypeX on BattleEffectType {
  String get dbValue => switch (this) {
        BattleEffectType.none => 'none',
        BattleEffectType.damage => 'damage',
        BattleEffectType.healing => 'healing',
        BattleEffectType.temporaryHp => 'temporary_hp',
        BattleEffectType.conditionApply => 'condition_apply',
        BattleEffectType.conditionRemove => 'condition_remove',
      };

  static BattleEffectType fromDb(String? value) => switch (value) {
        'damage' => BattleEffectType.damage,
        'healing' => BattleEffectType.healing,
        'temporary_hp' => BattleEffectType.temporaryHp,
        'condition_apply' => BattleEffectType.conditionApply,
        'condition_remove' => BattleEffectType.conditionRemove,
        _ => BattleEffectType.none,
      };
}

class BattleActionRequestModel {
  final int? id;
  final String syncId;
  final String battleSyncId;
  final String turnSyncId;
  final int turnSequence;
  final String actorCharacterSyncId;
  final BattleActionType actionType;
  final String actionSyncId;
  final String actionName;
  final BattleTargetType targetType;
  final String targetCharacterSyncId;
  final String targetLabel;
  final String attackFormula;
  final int? attackTotal;
  final String effectFormula;
  final BattleEffectType effectType;
  final int? effectTotal;
  final BattleActionRequestStatus status;
  final String resolutionNote;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final DateTime updatedAt;

  const BattleActionRequestModel({
    this.id,
    this.syncId = '',
    required this.battleSyncId,
    required this.turnSyncId,
    required this.turnSequence,
    required this.actorCharacterSyncId,
    required this.actionType,
    this.actionSyncId = '',
    required this.actionName,
    required this.targetType,
    this.targetCharacterSyncId = '',
    this.targetLabel = '',
    this.attackFormula = '',
    this.attackTotal,
    this.effectFormula = '',
    this.effectType = BattleEffectType.none,
    this.effectTotal,
    this.status = BattleActionRequestStatus.pendingGm,
    this.resolutionNote = '',
    this.metadata = const {},
    required this.createdAt,
    this.resolvedAt,
    required this.updatedAt,
  });

  BattleActionRequestModel copyWith({
    int? id,
    String? syncId,
    String? battleSyncId,
    String? turnSyncId,
    int? turnSequence,
    String? actorCharacterSyncId,
    BattleActionType? actionType,
    String? actionSyncId,
    String? actionName,
    BattleTargetType? targetType,
    String? targetCharacterSyncId,
    String? targetLabel,
    String? attackFormula,
    int? attackTotal,
    bool clearAttackTotal = false,
    String? effectFormula,
    BattleEffectType? effectType,
    int? effectTotal,
    bool clearEffectTotal = false,
    BattleActionRequestStatus? status,
    String? resolutionNote,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? resolvedAt,
    bool clearResolvedAt = false,
    DateTime? updatedAt,
  }) {
    return BattleActionRequestModel(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      battleSyncId: battleSyncId ?? this.battleSyncId,
      turnSyncId: turnSyncId ?? this.turnSyncId,
      turnSequence: turnSequence ?? this.turnSequence,
      actorCharacterSyncId: actorCharacterSyncId ?? this.actorCharacterSyncId,
      actionType: actionType ?? this.actionType,
      actionSyncId: actionSyncId ?? this.actionSyncId,
      actionName: actionName ?? this.actionName,
      targetType: targetType ?? this.targetType,
      targetCharacterSyncId: targetCharacterSyncId ?? this.targetCharacterSyncId,
      targetLabel: targetLabel ?? this.targetLabel,
      attackFormula: attackFormula ?? this.attackFormula,
      attackTotal: clearAttackTotal ? null : (attackTotal ?? this.attackTotal),
      effectFormula: effectFormula ?? this.effectFormula,
      effectType: effectType ?? this.effectType,
      effectTotal: clearEffectTotal ? null : (effectTotal ?? this.effectTotal),
      status: status ?? this.status,
      resolutionNote: resolutionNote ?? this.resolutionNote,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      resolvedAt: clearResolvedAt ? null : (resolvedAt ?? this.resolvedAt),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'sync_id': syncId,
        'battle_sync_id': battleSyncId,
        'turn_sync_id': turnSyncId,
        'turn_sequence': turnSequence,
        'actor_character_sync_id': actorCharacterSyncId,
        'action_type': actionType.dbValue,
        'action_sync_id': actionSyncId,
        'action_name': actionName,
        'target_type': targetType.dbValue,
        'target_character_sync_id': targetCharacterSyncId,
        'target_label': targetLabel,
        'attack_formula': attackFormula,
        'attack_total': attackTotal,
        'effect_formula': effectFormula,
        'effect_type': effectType.dbValue,
        'effect_total': effectTotal,
        'status': status.dbValue,
        'resolution_note': resolutionNote,
        'metadata': jsonEncode(metadata),
        'created_at': createdAt.toUtc().toIso8601String(),
        'resolved_at': resolvedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory BattleActionRequestModel.fromMap(Map<String, dynamic> map) {
    final rawMetadata = map['metadata'];
    Map<String, dynamic> metadata = const {};
    if (rawMetadata is Map) {
      metadata = rawMetadata.map((key, value) => MapEntry(key.toString(), value));
    } else if (rawMetadata is String && rawMetadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map) {
          metadata = decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }

    return BattleActionRequestModel(
      id: map['id'] as int?,
      syncId: map['sync_id']?.toString() ?? '',
      battleSyncId: map['battle_sync_id']?.toString() ?? '',
      turnSyncId: map['turn_sync_id']?.toString() ?? '',
      turnSequence: (map['turn_sequence'] as num?)?.toInt() ?? 0,
      actorCharacterSyncId: map['actor_character_sync_id']?.toString() ?? '',
      actionType: BattleActionTypeX.fromDb(map['action_type']?.toString()),
      actionSyncId: map['action_sync_id']?.toString() ?? '',
      actionName: map['action_name']?.toString() ?? '',
      targetType: BattleTargetTypeX.fromDb(map['target_type']?.toString()),
      targetCharacterSyncId: map['target_character_sync_id']?.toString() ?? '',
      targetLabel: map['target_label']?.toString() ?? '',
      attackFormula: map['attack_formula']?.toString() ?? '',
      attackTotal: (map['attack_total'] as num?)?.toInt(),
      effectFormula: map['effect_formula']?.toString() ?? '',
      effectType: BattleEffectTypeX.fromDb(map['effect_type']?.toString()),
      effectTotal: (map['effect_total'] as num?)?.toInt(),
      status: BattleActionRequestStatusX.fromDb(map['status']?.toString()),
      resolutionNote: map['resolution_note']?.toString() ?? '',
      metadata: metadata,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      resolvedAt: DateTime.tryParse(map['resolved_at']?.toString() ?? '')?.toLocal(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}
