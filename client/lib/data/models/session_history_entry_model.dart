import 'session_event_model.dart';
import 'battle_log_entry_model.dart';
import 'battle_model.dart';

class SessionHistoryEntryModel {
  final DateTime createdAt;
  final String kind;
  final String type;
  final String title;
  final String description;
  final String? actorCharacterSyncId;
  final String? targetCharacterSyncId;
  final BattleModel? battle;
  final List<BattleLogEntryModel> battleEntries;

  const SessionHistoryEntryModel({
    required this.createdAt,
    required this.kind,
    required this.type,
    required this.title,
    this.description = '',
    this.actorCharacterSyncId,
    this.targetCharacterSyncId,
    this.battle,
    this.battleEntries = const [],
  });

  factory SessionHistoryEntryModel.fromEvent(SessionEventModel event) => SessionHistoryEntryModel(
        createdAt: event.createdAt,
        kind: 'event',
        type: event.type,
        title: event.title,
        description: event.description,
      );

  factory SessionHistoryEntryModel.fromBattleGroup(
    BattleModel battle,
    List<BattleLogEntryModel> entries,
  ) {
    final name = battle.name.trim().isEmpty ? 'Бой' : battle.name.trim();
    return SessionHistoryEntryModel(
      createdAt: battle.startedAt ?? battle.createdAt,
      kind: 'battle',
      type: 'battle',
      title: name,
      battle: battle,
      battleEntries: List.unmodifiable(entries),
    );
  }

  factory SessionHistoryEntryModel.fromBattle(BattleLogEntryModel entry) {
    final title = switch (entry.type) {
      'turn_started' => 'Начат новый ход',
      'turn_ended' => 'Ход завершён',
      'action_submitted' => 'Игрок предложил действие',
      'action_approved' => 'Действие подтверждено',
      'action_modified' => 'Действие изменено ГМ',
      'action_rejected' => 'Действие отклонено',
      'attack_roll' => 'Брошена атака',
      'damage_roll' => 'Брошен урон',
      'healing_roll' => 'Брошено лечение',
      'damage_applied' => 'Применён урон',
      'healing_applied' => 'Применено лечение',
      'temporary_hp_applied' => 'Изменены временные хиты',
      _ => 'Событие боя',
    };
    final details = entry.targetLabel.isNotEmpty
        ? entry.targetLabel
        : (entry.amount != null ? '${entry.amount}' : '');
    return SessionHistoryEntryModel(
      createdAt: entry.createdAt,
      kind: 'battle',
      type: entry.type,
      title: title,
      description: details,
      actorCharacterSyncId: entry.actorCharacterSyncId.isEmpty ? null : entry.actorCharacterSyncId,
      targetCharacterSyncId: entry.targetCharacterSyncId.isEmpty ? null : entry.targetCharacterSyncId,
    );
  }
}
