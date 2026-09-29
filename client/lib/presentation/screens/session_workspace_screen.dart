import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/battle_log_entry_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/session_event_model.dart';
import '../../data/models/session_history_entry_model.dart';
import '../../data/models/session_loot_model.dart';
import '../../data/models/session_note_model.dart';
import '../../data/models/session_reward_model.dart';
import '../../data/models/session_model.dart';
import '../../domain/providers/campaign_provider.dart';
import '../../domain/providers/character_provider.dart';
import '../../domain/providers/session_provider.dart';
import '../../domain/providers/session_workspace_provider.dart';
import 'gm_battle_screen.dart';
import 'player_battle_screen.dart';
import 'gm_character_sheet_screen.dart';

class SessionWorkspaceScreen extends StatefulWidget {
  final SessionModel session;
  final bool gmMode;

  const SessionWorkspaceScreen({super.key, required this.session, required this.gmMode});

  @override
  State<SessionWorkspaceScreen> createState() => _SessionWorkspaceScreenState();
}

class _SessionWorkspaceScreenState extends State<SessionWorkspaceScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 7, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SessionWorkspaceProvider>().load(widget.session);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionProvider = context.watch<SessionProvider>();
    final workspace = context.watch<SessionWorkspaceProvider>();
    final characters = context.watch<CharacterProvider>().characters;
    final campaigns = context.watch<CampaignProvider>();
    final session = _findCurrentSession(sessionProvider) ?? widget.session;
    final currentGm = widget.gmMode;
    final linkedCharacterIds = campaigns.members
        .where((member) => member.role == CampaignRole.player && member.linkedCharacterId != null)
        .map((member) => member.linkedCharacterId!)
        .toSet();
    final campaignCharacters = characters
        .where((character) => character.id != null && linkedCharacterIds.contains(character.id))
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title),
            Text(
              '${session.status.label}${session.startedAt == null ? '' : ' · ${_dateTime(session.startedAt!)}'}',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
        actions: [
          if (session.id != null)
            IconButton(
              tooltip: workspace.loading ? 'Загрузка…' : 'Обновить',
              onPressed: workspace.loading ? null : () => workspace.load(session),
              icon: const Icon(Icons.refresh),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Обзор'),
            Tab(icon: Icon(Icons.menu_book_outlined), text: 'Журнал'),
            Tab(icon: Icon(Icons.event_note_outlined), text: 'События'),
            Tab(icon: Icon(Icons.star_outline), text: 'Награды'),
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Добыча'),
            Tab(icon: Icon(Icons.flash_on_outlined), text: 'Боевой режим'),
            Tab(icon: Icon(Icons.history_outlined), text: 'История'),
          ],
        ),
      ),
      body: workspace.loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(session: session, gmMode: currentGm, campaigns: campaigns, characters: characters, onEndSession: () => _endSession(context)),
                _JournalTab(gmMode: currentGm, notes: workspace.notes, onAdd: () => _addNote(context), onEdit: _editNote, onDelete: _deleteNote),
                _EventsTab(gmMode: currentGm, events: workspace.events, onAdd: () => _addEvent(context)),
                _RewardsTab(gmMode: currentGm, rewards: workspace.rewards, characters: campaignCharacters, onAdd: () => _grantXp(context)),
                _LootTab(gmMode: currentGm, loot: workspace.loot, characters: campaignCharacters, onAdd: () => _addLoot(context), onEdit: _editLoot, onDelete: _deleteLoot, onClaim: (loot) => _claimLoot(context, loot)),
                _BattleTab(session: session, gmMode: currentGm),
                _HistoryTab(entries: workspace.history, characters: campaignCharacters),
              ],
            ),
      floatingActionButton: currentGm ? _buildFab(context, session) : null,
    );
  }

  SessionModel? _findCurrentSession(SessionProvider provider) {
    for (final item in provider.sessions) {
      if (item.id == widget.session.id || (item.syncId.isNotEmpty && item.syncId == widget.session.syncId)) return item;
    }
    return null;
  }

  Widget? _buildFab(BuildContext context, SessionModel session) {
    return FloatingActionButton.extended(
      onPressed: () => _showQuickActions(context, session),
      icon: const Icon(Icons.add),
      label: const Text('Действие'),
    );
  }

  Future<void> _showQuickActions(BuildContext context, SessionModel session) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.menu_book_outlined), title: const Text('Добавить заметку'), onTap: () { Navigator.pop(sheetContext); _addNote(context); }),
            ListTile(leading: const Icon(Icons.event_note_outlined), title: const Text('Добавить событие'), onTap: () { Navigator.pop(sheetContext); _addEvent(context); }),
            ListTile(leading: const Icon(Icons.star_outline), title: const Text('Выдать XP'), onTap: () { Navigator.pop(sheetContext); _grantXp(context); }),
            ListTile(leading: const Icon(Icons.inventory_2_outlined), title: const Text('Добавить добычу'), onTap: () { Navigator.pop(sheetContext); _addLoot(context); }),
            ListTile(leading: const Icon(Icons.flash_on_outlined), title: const Text('Боевой режим'), onTap: () { Navigator.pop(sheetContext); _openBattle(context, session); }),
          ],
        ),
      ),
    );
  }

  Future<void> _addNote(BuildContext context) async {
    final result = await _noteDialog(context);
    if (result == null || !mounted) return;
    try {
      await context.read<SessionWorkspaceProvider>().addNote(title: result.$1, content: result.$2);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editNote(SessionNoteModel note) async {
    final result = await _noteDialog(context, existing: note);
    if (result == null || !mounted) return;
    try {
      await context.read<SessionWorkspaceProvider>().updateNote(note.copyWith(title: result.$1, content: result.$2));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteNote(SessionNoteModel note) async {
    if (await _confirm(context, 'Удалить заметку?', 'Заметка будет удалена из журнала.')) {
      try {
        await context.read<SessionWorkspaceProvider>().deleteNote(note);
      } catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _endSession(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      'Закончить сессию?',
      'Сессия будет отмечена как завершённая. Позже её можно будет возобновить.',
      confirmLabel: 'Закончить',
    );
    if (!confirmed || !mounted) return;
    try {
      await context.read<SessionProvider>().completeActive();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сессия завершена.')),
      );
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _addEvent(BuildContext context) async {
    final result = await _eventDialog(context);
    if (result == null || !mounted) return;
    try {
      await context.read<SessionWorkspaceProvider>().addEvent(title: result.$1, description: result.$2);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _grantXp(BuildContext context) async {
    final characters = context.read<CharacterProvider>().characters;
    final campaigns = context.read<CampaignProvider>();
    final linkedIds = campaigns.members
        .where((member) => member.role == CampaignRole.player && member.linkedCharacterId != null)
        .map((member) => member.linkedCharacterId!)
        .toSet();
    final campaignCharacters = characters
        .where((character) => character.id != null && linkedIds.contains(character.id))
        .toList(growable: false);
    if (campaignCharacters.isEmpty) {
      _showError(StateError('В кампании нет привязанных персонажей игроков.'));
      return;
    }
    final result = await _rewardDialog(context, campaignCharacters);
    if (result == null || !mounted) return;
    try {
      await context.read<SessionWorkspaceProvider>().grantXp(characterSyncId: result.$1, amount: result.$2, reason: result.$3);
      // Refresh the character list immediately because the authoritative XP
      // update is performed by the GM server when LAN mode is active.
      await context.read<CharacterProvider>().loadCharacters();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _addLoot(BuildContext context) async {
    final result = await _lootDialog(context);
    if (result == null || !mounted) return;
    try {
      await context.read<SessionWorkspaceProvider>().addLoot(name: result.$1, description: result.$2, quantity: result.$3, source: result.$4);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _editLoot(SessionLootModel loot) async {
    final result = await _lootDialog(context, existing: loot);
    if (result == null || !mounted) return;
    try {
      await context.read<SessionWorkspaceProvider>().updateLoot(loot.copyWith(name: result.$1, description: result.$2, quantity: result.$3, source: result.$4));
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _deleteLoot(SessionLootModel loot) async {
    if (await _confirm(context, 'Удалить добычу?', 'Запись о найденной добыче будет удалена.')) {
      try {
        await context.read<SessionWorkspaceProvider>().deleteLoot(loot);
      } catch (error) {
        _showError(error);
      }
    }
  }

  Future<void> _claimLoot(BuildContext context, SessionLootModel loot) async {
    final characters = context.read<CharacterProvider>().characters;
    final campaigns = context.read<CampaignProvider>();
    final linkedIds = campaigns.members
        .where((member) => member.role == CampaignRole.player && member.linkedCharacterId != null)
        .map((member) => member.linkedCharacterId!)
        .toSet();
    final campaignCharacters = characters
        .where((character) => character.id != null && linkedIds.contains(character.id))
        .toList(growable: false);
    if (campaignCharacters.isEmpty) {
      _showError(StateError('В кампании нет привязанных персонажей игроков.'));
      return;
    }
    final character = await _characterPicker(context, campaignCharacters, title: 'Кому выдать ${loot.name}?');
    if (character == null || !mounted) return;
    try {
      await context.read<SessionWorkspaceProvider>().claimLoot(lootSyncId: loot.syncId, characterSyncId: character.syncId);
    } catch (error) {
      _showError(error);
    }
  }

  void _openBattle(BuildContext context, SessionModel session) {
    if (session.id == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => widget.gmMode
          ? GmBattleScreen(campaignId: session.campaignId, sessionId: session.id!)
          : PlayerBattleScreen(campaignId: session.campaignId, sessionId: session.id!),
    ));
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _OverviewTab extends StatelessWidget {
  final SessionModel session;
  final bool gmMode;
  final CampaignProvider campaigns;
  final List<CharacterModel> characters;
  final VoidCallback? onEndSession;

  const _OverviewTab({
    required this.session,
    required this.gmMode,
    required this.campaigns,
    required this.characters,
    this.onEndSession,
  });

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<SessionWorkspaceProvider>();
    final linkedCharacters = <CharacterModel>[];
    final linkedIds = campaigns.members.where((m) => m.role == CampaignRole.player && m.linkedCharacterId != null).map((m) => m.linkedCharacterId!).toSet();
    for (final character in characters) {
      if (linkedIds.contains(character.id)) linkedCharacters.add(character);
    }
    final notesPreview = workspace.notes.take(3).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(session.status == SessionStatus.active ? Icons.radio_button_checked : Icons.history_outlined, color: session.status == SessionStatus.active ? AppTheme.success : AppTheme.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(session.status.label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 8),
          Text('Начало: ${_dateTime(session.startedAt)}'),
          Text('Завершение: ${_dateTime(session.endedAt)}'),
          if (session.status == SessionStatus.active && session.id != null && gmMode) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: !gmMode || onEndSession == null ? null : onEndSession,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Закончить сессию'),
              ),
            ),
          ],
        ]))),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 5 : (constraints.maxWidth >= 560 ? 3 : 2);
            return GridView.count(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _StatCard(icon: Icons.menu_book_outlined, label: 'Заметки', value: '${workspace.notes.length}'),
                _StatCard(icon: Icons.event_note_outlined, label: 'События', value: '${workspace.events.length}'),
                _StatCard(icon: Icons.inventory_2_outlined, label: 'Добыча', value: '${workspace.loot.length}'),
                _StatCard(icon: Icons.flash_on_outlined, label: 'Боёв', value: '${workspace.battleCount}'),
                _StatCard(icon: Icons.trending_up_outlined, label: 'Повышений уровня', value: '${workspace.levelUpCount}'),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Участники', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          if (linkedCharacters.isEmpty) const Text('Персонажи игроков ещё не привязаны.', style: TextStyle(color: AppTheme.textSecondary))
          else ...linkedCharacters.map((c) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(c.name),
            subtitle: Text('Уровень ${c.level} · HP ${c.hp}/${c.maxHp}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => GmCharacterSheetScreen(character: c)),
            ),
          )),
        ]))),
        if (notesPreview.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Последние заметки', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...notesPreview.map((note) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notes_outlined), title: Text(note.title), subtitle: Text(note.content, maxLines: 2, overflow: TextOverflow.ellipsis))),
          ]))),
        ],
        if (!gmMode) const Padding(padding: EdgeInsets.only(top: 16), child: Text('Режим игрока: информация сессии доступна для чтения. Изменения выполняет ГМ.', style: TextStyle(color: AppTheme.textSecondary))),
      ],
    );
  }

  void _openBattle(BuildContext context, SessionModel session) {
    if (session.id == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => gmMode ? GmBattleScreen(campaignId: session.campaignId, sessionId: session.id!) : PlayerBattleScreen(campaignId: session.campaignId, sessionId: session.id!)));
  }
}

class _JournalTab extends StatelessWidget {
  final bool gmMode;
  final List<SessionNoteModel> notes;
  final VoidCallback onAdd;
  final Future<void> Function(SessionNoteModel) onEdit;
  final Future<void> Function(SessionNoteModel) onDelete;
  const _JournalTab({required this.gmMode, required this.notes, required this.onAdd, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Row(children: [const Expanded(child: Text('Журнал сессии', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))), if (gmMode) FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Заметка'))]),
    const SizedBox(height: 10),
    if (notes.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Заметок пока нет.', style: TextStyle(color: AppTheme.textSecondary))))
    else ...notes.map((note) => Card(child: ListTile(leading: const Icon(Icons.notes_outlined), title: Text(note.title), subtitle: Text(note.content, maxLines: 4, overflow: TextOverflow.ellipsis), trailing: gmMode ? PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') onEdit(note); if (v == 'delete') onDelete(note); }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Редактировать')), PopupMenuItem(value: 'delete', child: Text('Удалить'))]) : null, onTap: gmMode ? () => onEdit(note) : null)))
  ]);
}

class _EventsTab extends StatelessWidget {
  final bool gmMode;
  final List<SessionEventModel> events;
  final VoidCallback onAdd;

  const _EventsTab({required this.gmMode, required this.events, required this.onAdd});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Игровые события',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
              ),
              if (gmMode)
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Событие'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (events.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Событий пока нет.',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            ...events.map(
              (event) => Card(
                child: ListTile(
                  leading: const Icon(Icons.event_note_outlined),
                  title: Text(event.title),
                  subtitle: Text(
                    [event.description, event.createdBy]
                        .where((value) => value.trim().isNotEmpty)
                        .join(' · '),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _time(event.createdAt),
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ),
            ),
        ],
      );
}

class _BattleTab extends StatelessWidget {
  final SessionModel session;
  final bool gmMode;

  const _BattleTab({required this.session, required this.gmMode});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flash_on_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text(
                      'Боевой режим',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Бой остаётся отдельной рабочей областью внутри этой сессии. Откройте его, чтобы управлять инициативой, ходами и действиями.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: session.id == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => gmMode
                                      ? GmBattleScreen(
                                          campaignId: session.campaignId,
                                          sessionId: session.id!,
                                        )
                                      : PlayerBattleScreen(
                                          campaignId: session.campaignId,
                                          sessionId: session.id!,
                                        ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.flash_on),
                      label: const Text('Открыть боевой режим'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _RewardsTab extends StatelessWidget {
  final bool gmMode;
  final List<SessionRewardModel> rewards;
  final List<CharacterModel> characters;
  final VoidCallback onAdd;
  const _RewardsTab({required this.gmMode, required this.rewards, required this.characters, required this.onAdd});

  String _name(String syncId) {
    for (final c in characters) { if (c.syncId == syncId) return c.name; }
    return syncId.isEmpty ? 'Персонаж' : syncId;
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Row(children: [const Expanded(child: Text('Награды', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))), if (gmMode) FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('XP'))]),
    const SizedBox(height: 10),
    if (rewards.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Наград пока нет.', style: TextStyle(color: AppTheme.textSecondary))))
    else ...rewards.map((reward) => Card(child: ListTile(leading: const Icon(Icons.star_outline), title: Text(reward.type == 'xp' ? '+${reward.amount} XP' : '${reward.amount}'), subtitle: Text('${_name(reward.characterSyncId)}${reward.reason.trim().isEmpty ? '' : ' · ${reward.reason}'}'), trailing: Text(_time(reward.createdAt), style: const TextStyle(color: AppTheme.textSecondary)))))
  ]);
}

class _LootTab extends StatelessWidget {
  final bool gmMode;
  final List<SessionLootModel> loot;
  final List<CharacterModel> characters;
  final VoidCallback onAdd;
  final Future<void> Function(SessionLootModel) onEdit;
  final Future<void> Function(SessionLootModel) onDelete;
  final Future<void> Function(SessionLootModel) onClaim;
  const _LootTab({required this.gmMode, required this.loot, required this.characters, required this.onAdd, required this.onEdit, required this.onDelete, required this.onClaim});

  String _name(String? syncId) {
    if (syncId == null || syncId.isEmpty) return '';
    for (final c in characters) { if (c.syncId == syncId) return c.name; }
    return syncId;
  }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
    Row(children: [const Expanded(child: Text('Добыча', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))), if (gmMode) FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Добыча'))]),
    const SizedBox(height: 10),
    if (loot.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Добычи пока нет.', style: TextStyle(color: AppTheme.textSecondary))))
    else ...loot.map((item) => Card(child: ListTile(
      leading: Icon(item.status == 'claimed' ? Icons.check_circle_outline : Icons.inventory_2_outlined, color: item.status == 'claimed' ? AppTheme.success : null),
      title: Text('${item.name} ×${item.quantity}'),
      subtitle: Text(item.status == 'claimed' ? 'Выдано: ${_name(item.claimedByCharacterSyncId)}${item.source.isEmpty ? '' : ' · Источник: ${item.source}'}' : (item.source.isEmpty ? 'Доступно для распределения' : 'Источник: ${item.source}')),
      trailing: gmMode ? (item.status == 'available' ? PopupMenuButton<String>(onSelected: (v) { if (v == 'claim') onClaim(item); if (v == 'edit') onEdit(item); if (v == 'delete') onDelete(item); }, itemBuilder: (_) => const [PopupMenuItem(value: 'claim', child: Text('Выдать персонажу')), PopupMenuItem(value: 'edit', child: Text('Редактировать')), PopupMenuItem(value: 'delete', child: Text('Удалить'))]) : const Icon(Icons.check)) : null,
    )))
  ]);
}

class _HistoryTab extends StatelessWidget {
  final List<SessionHistoryEntryModel> entries;
  final List<CharacterModel> characters;

  const _HistoryTab({required this.entries, required this.characters});

  String _name(String? syncId) {
    if (syncId == null || syncId.isEmpty) return '';
    for (final c in characters) {
      if (c.syncId == syncId) return c.name;
    }
    return '';
  }

  IconData _icon(SessionHistoryEntryModel entry) {
    if (entry.kind == 'battle') return Icons.flash_on_outlined;
    switch (entry.type) {
      case 'reward_granted':
      case 'xp_awarded':
        return Icons.star_outline;
      case 'loot_added':
      case 'loot_claimed':
      case 'item_granted':
        return Icons.inventory_2_outlined;
      case 'note_created':
        return Icons.notes_outlined;
      default:
        return Icons.event_note_outlined;
    }
  }

  String _battleIcon(String type) => switch (type) {
        'turn_started' => '▶',
        'turn_ended' => '■',
        'action_submitted' => '⚡',
        'action_approved' => '✓',
        'action_modified' => '✎',
        'action_rejected' => '✕',
        'attack_roll' => '🎲',
        'damage_roll' => '⚔',
        'healing_roll' => '✚',
        'damage_applied' => '♥',
        'healing_applied' => '＋',
        'temporary_hp_applied' => '▣',
        _ => '•',
      };

  String _battleText(BattleLogEntryModel entry) {
    final actor = _name(entry.actorCharacterSyncId);
    final target = entry.targetLabel.isNotEmpty
        ? entry.targetLabel
        : _name(entry.targetCharacterSyncId);
    final actorText = actor.isEmpty ? '' : actor;
    final targetText = target.isEmpty ? '' : target;
    final route = [actorText, targetText]
        .where((value) => value.isNotEmpty)
        .join(' → ');
    String action = switch (entry.type) {
      'turn_started' => 'Начат ход',
      'turn_ended' => 'Ход завершён',
      'action_submitted' => 'Предложено действие',
      'action_approved' => 'Действие подтверждено',
      'action_modified' => 'Действие изменено ГМ',
      'action_rejected' => 'Действие отклонено',
      'attack_roll' => 'Бросок атаки',
      'damage_roll' => 'Бросок урона',
      'healing_roll' => 'Бросок лечения',
      'damage_applied' => 'Применён урон',
      'healing_applied' => 'Применено лечение',
      'temporary_hp_applied' => 'Изменены временные хиты',
      _ => 'Событие боя',
    };
    if (entry.amount != null) action = '$action · ${entry.amount}';
    if (route.isNotEmpty) action = '$action · $route';
    return action;
  }

  String _battleSummary(SessionHistoryEntryModel entry) {
    final battle = entry.battle!;
    final start = battle.startedAt ?? battle.createdAt;
    final end = battle.endedAt;
    if (end == null) {
      return '${_time(start)} · ${entry.battleEntries.length} записей';
    }
    return '${_time(start)}–${_time(end)} · ${entry.battleEntries.length} записей';
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'История пока пуста.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry.kind == 'battle' && entry.battle != null) {
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              leading: const Icon(Icons.flash_on_outlined),
              title: Text(entry.title),
              subtitle: Text(_battleSummary(entry)),
              children: [
                if (entry.battleEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'В этом бою пока нет записей действий.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  )
                else
                  for (final battleEntry in entry.battleEntries)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            child: Text(
                              _battleIcon(battleEntry.type),
                              style: const TextStyle(fontSize: 17),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_battleText(battleEntry))),
                          const SizedBox(width: 8),
                          Text(
                            _time(battleEntry.createdAt),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          );
        }

        final actor = _name(entry.actorCharacterSyncId);
        final target = _name(entry.targetCharacterSyncId);
        final suffix = [actor, target]
            .where((value) => value.isNotEmpty)
            .join(' → ');
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: Icon(_icon(entry)),
            title: Text(entry.title),
            subtitle: Text(
              [entry.description, suffix]
                  .where((value) => value.isNotEmpty)
                  .join(' · '),
            ),
            trailing: Text(
              _time(entry.createdAt),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [Icon(icon, color: AppTheme.accent), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)), Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18))]))])));
}

Future<(String, String)?> _noteDialog(BuildContext context, {SessionNoteModel? existing}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final content = TextEditingController(text: existing?.content ?? '');
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(existing == null ? 'Новая заметка' : 'Редактировать заметку'),
      content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Заголовок')), const SizedBox(height: 10), TextField(controller: content, minLines: 5, maxLines: 12, decoration: const InputDecoration(labelText: 'Текст', alignLabelWithHint: true))])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, (title.text, content.text)), child: const Text('Сохранить'))],
    ),
  );
  title.dispose(); content.dispose();
  return result;
}

Future<(String, String)?> _eventDialog(BuildContext context) async {
  final title = TextEditingController();
  final description = TextEditingController();
  final result = await showDialog<(String, String)>(context: context, builder: (_) => AlertDialog(title: const Text('Игровое событие'), content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Событие')), const SizedBox(height: 10), TextField(controller: description, minLines: 3, maxLines: 8, decoration: const InputDecoration(labelText: 'Описание'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, (title.text, description.text)), child: const Text('Добавить'))]));
  title.dispose(); description.dispose();
  return result;
}

Future<(String, int, String)?> _rewardDialog(BuildContext context, List<CharacterModel> characters) async {
  final amount = TextEditingController(text: '100');
  final reason = TextEditingController();
  String? characterSyncId = characters.isEmpty ? null : characters.first.syncId;
  final result = await showDialog<(String, int, String)>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setState) => AlertDialog(title: const Text('Выдать XP'), content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [DropdownButtonFormField<String>(value: characterSyncId, items: [for (final c in characters) DropdownMenuItem(value: c.syncId, child: Text('${c.name} · ур. ${c.level}'))], onChanged: (v) => setState(() => characterSyncId = v), decoration: const InputDecoration(labelText: 'Персонаж')), const SizedBox(height: 10), TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'XP')), const SizedBox(height: 10), TextField(controller: reason, decoration: const InputDecoration(labelText: 'Причина'))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () { final parsed = int.tryParse(amount.text.trim()); if (characterSyncId == null || parsed == null || parsed <= 0) return; Navigator.pop(context, (characterSyncId!, parsed, reason.text)); }, child: const Text('Выдать'))])));
  amount.dispose(); reason.dispose();
  return result;
}

Future<(String, String, int, String)?> _lootDialog(BuildContext context, {SessionLootModel? existing}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final quantity = TextEditingController(text: '${existing?.quantity ?? 1}');
  final source = TextEditingController(text: existing?.source ?? '');
  final result = await showDialog<(String, String, int, String)>(context: context, builder: (_) => AlertDialog(title: Text(existing == null ? 'Добавить добычу' : 'Редактировать добычу'), content: SizedBox(width: 520, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Название')), const SizedBox(height: 10), TextField(controller: description, minLines: 2, maxLines: 5, decoration: const InputDecoration(labelText: 'Описание')), const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Количество'))), const SizedBox(width: 10), Expanded(child: TextField(controller: source, decoration: const InputDecoration(labelText: 'Источник')))] )])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () { final q = int.tryParse(quantity.text.trim()); if (name.text.trim().isEmpty || q == null || q <= 0) return; Navigator.pop(context, (name.text, description.text, q, source.text)); }, child: const Text('Сохранить'))]));
  name.dispose(); description.dispose(); quantity.dispose(); source.dispose();
  return result;
}

Future<CharacterModel?> _characterPicker(BuildContext context, List<CharacterModel> characters, {required String title}) async => showDialog<CharacterModel>(context: context, builder: (_) => SimpleDialog(title: Text(title), children: [for (final character in characters) SimpleDialogOption(onPressed: () => Navigator.pop(context, character), child: Text('${character.name} · ур. ${character.level}'))]));

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message, {
  String confirmLabel = 'Удалить',
}) async =>
    await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;

String _dateTime(DateTime? value) => value == null ? '—' : '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year} ${_time(value)}';
String _time(DateTime value) => '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
