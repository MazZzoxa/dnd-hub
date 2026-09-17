import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/character_avatar.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/session_model.dart';
import '../../domain/providers/campaign_provider.dart';
import '../../domain/providers/character_provider.dart';
import '../../domain/providers/session_provider.dart';
import 'campaign_home_screen.dart';
import 'gm_character_sheet_screen.dart';

class GmDashboardScreen extends StatefulWidget {
  const GmDashboardScreen({super.key});

  @override
  State<GmDashboardScreen> createState() => _GmDashboardScreenState();
}

class _GmDashboardScreenState extends State<GmDashboardScreen> {
  int _index = 0;
  final _destinations = const [
    (icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Обзор'),
    (icon: Icons.groups_outlined, selectedIcon: Icons.groups, label: 'Игроки'),
    (icon: Icons.play_circle_outline, selectedIcon: Icons.play_circle, label: 'Сессия'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final campaign = context.read<CampaignProvider>().selected;
      if (campaign?.id != null) {
        await context.read<SessionProvider>().load(campaign!.id!);
        if (context.read<CharacterProvider>().characters.isEmpty) {
          await context.read<CharacterProvider>().loadCharacters();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignProvider>().selected;
    if (campaign == null) {
      return const Scaffold(body: Center(child: Text('Кампания не выбрана')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('GM · ${campaign.name}'),
        actions: [
          IconButton(
            tooltip: 'Управление кампанией',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CampaignHomeScreen())),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 800;
          if (wide) {
            return Row(children: [
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (value) => setState(() => _index = value),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final item in _destinations)
                    NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(item.label),
                    )
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _body(_index, campaign.id!)),
            ]);
          }
          return _body(_index, campaign.id!);
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 800) return const SizedBox.shrink();
          return BottomNavigationBar(
            currentIndex: _index,
            onTap: (value) => setState(() => _index = value),
            items: [for (final item in _destinations) BottomNavigationBarItem(icon: Icon(item.icon), label: item.label)],
          );
        },
      ),
    );
  }

  Widget _body(int index, int campaignId) {
    switch (index) {
      case 1:
        return _PlayersView(campaignId: campaignId);
      case 2:
        return _SessionView(campaignId: campaignId);
      default:
        return _OverviewView(campaignId: campaignId, onOpenSession: () => setState(() => _index = 2));
    }
  }
}

class _OverviewView extends StatelessWidget {
  final int campaignId;
  final VoidCallback onOpenSession;
  const _OverviewView({required this.campaignId, required this.onOpenSession});

  @override
  Widget build(BuildContext context) {
    final campaigns = context.watch<CampaignProvider>();
    final characters = context.watch<CharacterProvider>();
    final sessions = context.watch<SessionProvider>();
    final playerCount = campaigns.members.where((member) => member.role == CampaignRole.player).length;
    final linkedCount = campaigns.members.where((member) => member.role == CampaignRole.player && member.linkedCharacterId != null).length;
    final active = sessions.active;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.shield_outlined, color: AppTheme.primary), SizedBox(width: 8), Text('GM Dashboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))]),
              const SizedBox(height: 8),
              Text(campaigns.selected?.description.isEmpty == false ? campaigns.selected!.description : 'Управление локальной кампанией и игровыми сессиями.', style: const TextStyle(color: AppTheme.textSecondary)),
              const SizedBox(height: 18),
              Wrap(spacing: 10, runSpacing: 10, children: [
                _Metric(label: 'Игроков', value: '$playerCount', icon: Icons.person_outline),
                _Metric(label: 'Персонажей', value: '${characters.characters.length}', icon: Icons.shield_outlined),
                _Metric(label: 'Привязано', value: '$linkedCount', icon: Icons.link_outlined),
                _Metric(label: 'Сессий', value: '${sessions.sessions.length}', icon: Icons.history_outlined),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _ActiveSessionCard(campaignId: campaignId, active: active, onOpenSession: onOpenSession),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.settings_outlined, color: AppTheme.accent),
            title: const Text('Управление кампанией'),
            subtitle: const Text('Участники, роли, имена и привязка персонажей'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CampaignHomeScreen())),
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Metric({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        width: 148,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.surfaceVariant, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [Icon(icon, color: AppTheme.accent, size: 18), const SizedBox(width: 9), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)), Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))])]),
      );
}

class _ActiveSessionCard extends StatelessWidget {
  final int campaignId;
  final SessionModel? active;
  final VoidCallback onOpenSession;
  const _ActiveSessionCard({required this.campaignId, required this.active, required this.onOpenSession});

  @override
  Widget build(BuildContext context) {
    if (active == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Сессия', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), SizedBox(height: 4), Text('Активной сессии сейчас нет.', style: TextStyle(color: AppTheme.textSecondary))])),
            FilledButton.icon(onPressed: () => _start(context), icon: const Icon(Icons.play_arrow), label: const Text('Начать')),
          ]),
        ),
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.radio_button_checked, color: AppTheme.success),
        title: Text(active!.title),
        subtitle: Text('Начата ${_format(active!.startedAt)}'),
        trailing: FilledButton(onPressed: onOpenSession, child: const Text('Открыть')),
        onTap: onOpenSession,
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    final controller = TextEditingController(text: 'Игровая сессия');
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Начать сессию'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Название')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Начать'))],
      ),
    );
    controller.dispose();
    if (title == null || !context.mounted) return;
    try {
      await context.read<SessionProvider>().startSession(campaignId: campaignId, title: title);
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

}

CampaignMemberModel? _findGm(List<CampaignMemberModel> members) {
  for (final member in members) {
    if (member.role == CampaignRole.gm) return member;
  }
  return null;
}

class _PlayersView extends StatelessWidget {
  final int campaignId;
  const _PlayersView({required this.campaignId});

  CharacterModel? _find(List<CharacterModel> characters, int? id) {
    if (id == null) return null;
    for (final character in characters) {
      if (character.id == id) return character;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final campaigns = context.watch<CampaignProvider>();
    final characters = context.watch<CharacterProvider>().characters;
    final members = campaigns.members.where((member) => member.role == CampaignRole.player).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [const Expanded(child: Text('Игроки и персонажи', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))), FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CampaignHomeScreen())), icon: const Icon(Icons.settings_outlined), label: const Text('Управление'))]),
        const SizedBox(height: 12),
        if (members.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('В кампании пока нет игроков.', style: TextStyle(color: AppTheme.textSecondary))))
        else
          ...members.map((member) {
            final character = _find(characters, member.linkedCharacterId);
            return _PlayerCard(member: member, character: character);
          }),
        const SizedBox(height: 12),
        _GmMemberCard(member: _findGm(campaigns.members)),
      ],
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final CampaignMemberModel member;
  final CharacterModel? character;
  const _PlayerCard({required this.member, required this.character});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(children: [
          character == null
              ? const CircleAvatar(child: Icon(Icons.person_outline))
              : CharacterAvatar(character: character!, radius: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(member.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              if (character == null)
                const Text('Персонаж не привязан', style: TextStyle(color: AppTheme.textSecondary))
              else ...[
                Text('${character!.name} · ур. ${character!.level}', style: const TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                Text('HP ${character!.hp}/${character!.maxHp} · AC ${character!.armorClass} · Инициатива ${character!.initiative >= 0 ? '+' : ''}${character!.initiative}', style: const TextStyle(fontSize: 13)),
              ],
            ]),
          ),
          if (character != null) IconButton(tooltip: 'Открыть лист', icon: const Icon(Icons.visibility_outlined), onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GmCharacterSheetScreen(character: character!)))),
        ]),
      ),
    );
  }
}

class _GmMemberCard extends StatelessWidget {
  final CampaignMemberModel? member;
  const _GmMemberCard({required this.member});

  @override
  Widget build(BuildContext context) {
    if (member == null) return const SizedBox.shrink();
    return Card(child: ListTile(leading: const Icon(Icons.shield_outlined, color: AppTheme.primary), title: Text('GM: ${member!.name}'), subtitle: const Text('Текущий GM кампании')));
  }
}

class _SessionView extends StatefulWidget {
  final int campaignId;
  const _SessionView({required this.campaignId});

  @override
  State<_SessionView> createState() => _SessionViewState();
}

class _SessionViewState extends State<_SessionView> {
  final _notes = TextEditingController();
  final _title = TextEditingController();
  int? _loadedSessionId;
  bool _saving = false;

  @override
  void dispose() {
    _notes.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SessionProvider>();
    final active = provider.active;
    if (active != null && _loadedSessionId != active.id) {
      _loadedSessionId = active.id;
      _title.text = active.title;
      _notes.text = active.notes;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [const Expanded(child: Text('Session Tools', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))), if (active == null) FilledButton.icon(onPressed: () => _start(context), icon: const Icon(Icons.play_arrow), label: const Text('Начать сессию'))]),
        const SizedBox(height: 12),
        if (active == null)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Активной сессии нет. Создайте её перед игрой.', style: TextStyle(color: AppTheme.textSecondary))))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [const Icon(Icons.radio_button_checked, color: AppTheme.success), const SizedBox(width: 8), const Text('Активная сессия', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)), const Spacer(), Text(_format(active.startedAt), style: const TextStyle(color: AppTheme.textSecondary))]),
                const SizedBox(height: 14),
                TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название сессии')),
                const SizedBox(height: 12),
                TextField(controller: _notes, minLines: 8, maxLines: 16, decoration: const InputDecoration(labelText: 'Заметки GM', alignLabelWithHint: true, hintText: 'NPC, события, решения игроков, награды и другие заметки по ходу игры…')),
                const SizedBox(height: 14),
                Row(children: [FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Сохранение…' : 'Сохранить')), const SizedBox(width: 10), OutlinedButton.icon(onPressed: () => _complete(context), icon: const Icon(Icons.stop_circle_outlined), label: const Text('Завершить'))]),
              ]),
            ),
          ),
        const SizedBox(height: 14),
        const Text('История сессий', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...provider.sessions.map((session) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(session.status == SessionStatus.active ? Icons.play_circle : Icons.history, color: session.status == SessionStatus.active ? AppTheme.success : AppTheme.textSecondary),
                title: Text(session.title),
                subtitle: Text('${session.status.label} · ${_format(session.startedAt ?? session.createdAt)}'),
              ),
            )),
      ],
    );
  }

  Future<void> _start(BuildContext context) async {
    final controller = TextEditingController(text: 'Игровая сессия');
    final title = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Начать сессию'), content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Название')), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Начать'))]));
    controller.dispose();
    if (title == null || !context.mounted) return;
    try {
      await context.read<SessionProvider>().startSession(campaignId: widget.campaignId, title: title);
      _loadedSessionId = null;
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<SessionProvider>().updateActive(title: _title.text, notes: _notes.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Сессия сохранена')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _complete(BuildContext context) async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Завершить сессию?'), content: const Text('Текущие заметки сохранятся, а сессия перейдёт в историю.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Завершить'))]));
    if (confirmed != true || !context.mounted) return;
    await context.read<SessionProvider>().updateActive(title: _title.text, notes: _notes.text);
    await context.read<SessionProvider>().completeActive();
    _loadedSessionId = null;
  }
}

String _format(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day.$month.${local.year} $hour:$minute';
}
