import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/battle_action_request_model.dart';
import '../../data/models/session_model.dart';
import '../../domain/battle/dice_service.dart';
import '../../domain/providers/battle_provider.dart';
import '../../domain/providers/campaign_provider.dart';
import '../../domain/providers/character_provider.dart';
import '../../domain/providers/session_provider.dart';
import '../widgets/battle_action_sheet.dart';
import '../widgets/battle_character_card.dart';
import '../widgets/battle_toolbar.dart';
import '../widgets/battle_workspace_widgets.dart';
import '../widgets/dice_roller_sheet.dart';
import 'battle_character_view_screen.dart';

class GmBattleScreen extends StatefulWidget {
  final int campaignId;
  final int sessionId;

  const GmBattleScreen({
    super.key,
    required this.campaignId,
    required this.sessionId,
  });

  @override
  State<GmBattleScreen> createState() => _GmBattleScreenState();
}

class _GmBattleScreenState extends State<GmBattleScreen> {
  final DiceService _dice = DiceService();
  bool _loadingAction = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<BattleProvider>().loadForSession(
            campaignId: widget.campaignId,
            sessionId: widget.sessionId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final campaign = context.watch<CampaignProvider>().selected;
    final sessionProvider = context.watch<SessionProvider>();
    final battle = context.watch<BattleProvider>();

    if (campaign == null) {
      return const Scaffold(body: Center(child: Text('Кампания не выбрана')));
    }

    final session = _findSession(sessionProvider.sessions, widget.sessionId);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              battle.active?.name.trim().isNotEmpty == true
                  ? '⚔ ${battle.active!.name}'
                  : '⚔ Боевой режим · ГМ',
            ),
            Text(
              session?.title ?? 'Сессия',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
      body: battle.active == null
          ? _inactiveBody(session)
          : _activeBody(battle: battle),
    );
  }

  SessionModel? _findSession(List<SessionModel> sessions, int id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  Widget _inactiveBody(SessionModel? session) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sports_kabaddi_outlined, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'Активного боя нет',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  session?.status == SessionStatus.active
                      ? 'Запустите боевой режим для текущей сессии.'
                      : 'Бой можно начать только внутри активной сессии.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                if (session?.status == SessionStatus.active) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _startBattle(session!),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Начать бой'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeBody({required BattleProvider battle}) {
    final campaigns = context.watch<CampaignProvider>();
    final characters = context.watch<CharacterProvider>().characters;
    final linkedCharacters = <CharacterModel>[];

    for (final member in campaigns.members.where(
      (item) => item.role == CampaignRole.player,
    )) {
      final id = member.linkedCharacterId;
      if (id == null) continue;
      for (final character in characters) {
        if (character.id == id) {
          linkedCharacters.add(character);
          break;
        }
      }
    }

    CharacterModel? findCharacter(String syncId) {
      for (final character in linkedCharacters) {
        if (character.syncId == syncId) return character;
      }
      return null;
    }

    final currentTurnCharacter = battle.currentTurn == null
        ? null
        : findCharacter(battle.currentTurn!.characterSyncId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.radio_button_checked, color: AppTheme.success),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Бой активен',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${linkedCharacters.length} персонажей',
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        BattleToolbar(
          onDice: _rollDice,
          canEndBattle: true,
          onEndBattle: () => _endBattle(battle),
        ),
        const SizedBox(height: 12),
        if (battle.currentTurn != null)
          BattleCurrentTurnCard(
            characterName: currentTurnCharacter?.name ?? 'Персонаж',
            sequence: battle.currentTurn!.sequence,
            canEnd: true,
            onEnd: () => _endTurn(battle),
          )
        else
          const Card(
            child: ListTile(
              leading: Icon(Icons.hourglass_empty),
              title: Text('Ход не назначен'),
              subtitle: Text(
                'Выберите персонажа ниже и нажмите «Дать ход».',
              ),
            ),
          ),
        const SizedBox(height: 12),
        _sectionTitle(
          'Запросы действий',
          Icons.flash_on_outlined,
          battle.pendingActionRequests.length,
        ),
        const SizedBox(height: 8),
        if (battle.pendingActionRequests.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Нет действий, ожидающих решения ГМ.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          ...[
            for (final request in battle.pendingActionRequests)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BattleActionRequestCard(
                  request: request,
                  actorName: _nameForSync(
                    request.actorCharacterSyncId,
                    linkedCharacters,
                  ),
                  targetName: _requestTargetName(request, linkedCharacters),
                  onApprove: () => _approve(battle, request),
                  onModify: () => _modify(battle, request, linkedCharacters),
                  onReject: () => _reject(battle, request),
                ),
              ),
          ],
        const SizedBox(height: 4),
        _sectionTitle('Группа', Icons.groups_outlined, linkedCharacters.length),
        const SizedBox(height: 8),
        if (linkedCharacters.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'В кампании пока нет привязанных персонажей игроков.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final itemWidth = width >= 900
                  ? (width - 16) / 2
                  : width >= 560
                      ? (width - 16) / 2
                      : width;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final character in linkedCharacters)
                    SizedBox(
                      width: itemWidth,
                      child: _partyCharacter(
                        battle,
                        character,
                        currentTurnCharacter?.syncId == character.syncId,
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 18),
        BattleJournalList(
          entries: battle.journal,
          gmDetailed: true,
          characterName: (syncId) => _nameForSync(syncId, linkedCharacters),
        ),
        if (battle.lastDice != null) ...[
          const SizedBox(height: 14),
          _diceResult(battle.lastDice!),
        ],
        const SizedBox(height: 20),
        const Text(
          'Боевой режим хранит состояние, ход, запросы действий и историю. Решение правил остаётся за ГМ.',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _partyCharacter(
    BattleProvider battle,
    CharacterModel character,
    bool isCurrentTurn,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => BattleCharacterViewScreen(
                character: character,
                canAct: false,
              ),
            ),
          ),
          child: BattleCharacterCard.fromCharacter(
            character: character,
            canEdit: true,
            onDamage: () => _action(
              battle,
              character,
              BattleActionKind.damage,
            ),
            onHeal: () => _action(
              battle,
              character,
              BattleActionKind.heal,
            ),
            onTemporaryHp: () => _action(
              battle,
              character,
              BattleActionKind.temporaryHp,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: isCurrentTurn
              ? null
              : () => _startTurn(battle, character),
          icon: Icon(
            isCurrentTurn ? Icons.flash_on : Icons.play_arrow_outlined,
          ),
          label: Text(isCurrentTurn ? 'Текущий ход' : 'Дать ход'),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title, IconData icon, int count) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  String _nameForSync(String syncId, List<CharacterModel> characters) {
    for (final character in characters) {
      if (character.syncId == syncId) return character.name;
    }
    return syncId.isEmpty ? '—' : syncId;
  }

  String _requestTargetName(
    request,
    List<CharacterModel> characters,
  ) {
    if (request.targetType == BattleTargetType.external) return request.targetLabel;
    return _nameForSync(request.targetCharacterSyncId, characters);
  }

  Widget _diceResult(DiceDisplay result) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.casino_outlined),
        title: Text('${result.expression} = ${result.total}'),
        subtitle: Text(
          'Броски: ${result.rolls.join(', ')}'
          '${result.modifier == 0 ? '' : ' · Модификатор ${result.modifier >= 0 ? '+' : ''}${result.modifier}'}',
        ),
      ),
    );
  }

  Future<void> _startTurn(BattleProvider provider, CharacterModel character) async {
    try {
      await provider.startTurn(characterSyncId: character.syncId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _endTurn(BattleProvider provider) async {
    try {
      await provider.endTurn();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _approve(
    BattleProvider provider,
    request,
  ) async {
    try {
      await provider.approveAction(request);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _modify(
    BattleProvider provider,
    request,
    List<CharacterModel> characters,
  ) async {
    final result = await showBattleActionReviewDialog(
      context,
      request: request,
      allies: characters,
    );
    if (result == null || !mounted) return;
    try {
      await provider.modifyAction(
        request,
        modifications: result.modifications,
        note: result.note,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _reject(BattleProvider provider, request) async {
    final reason = await _reasonDialog('Отклонить действие', 'Причина');
    if (reason == null || !mounted) return;
    try {
      await provider.rejectAction(request, reason: reason);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<String?> _reasonDialog(String title, String hint) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
          decoration: InputDecoration(labelText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _action(
    BattleProvider provider,
    CharacterModel character,
    BattleActionKind kind,
  ) async {
    if (_loadingAction) return;
    final value = await showBattleActionSheet(
      context,
      kind: kind,
      characterName: character.name,
    );
    if (value == null || !mounted) return;

    setState(() => _loadingAction = true);
    try {
      switch (kind) {
        case BattleActionKind.damage:
          await provider.damage(characterSyncId: character.syncId, amount: value);
          break;
        case BattleActionKind.heal:
          await provider.heal(characterSyncId: character.syncId, amount: value);
          break;
        case BattleActionKind.temporaryHp:
          await provider.setTemporaryHp(characterSyncId: character.syncId, amount: value);
          break;
      }
      await context.read<CharacterProvider>().loadCharacters();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _loadingAction = false);
    }
  }

  Future<void> _startBattle(SessionModel session) async {
    final controller = TextEditingController(text: 'Бой');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Начать бой'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(
            labelText: 'Название боя',
            hintText: 'Например, Бой у северных ворот',
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Начать'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      await context.read<BattleProvider>().startBattle(session, name: name);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _endBattle(BattleProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Завершить бой?'),
        content: const Text(
          'Бой завершится. Текущая сессия продолжит работать.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await provider.endBattle();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _rollDice() async {
    final result = await showDiceRoller(context, service: _dice);
    if (result == null || !mounted) return;
    context.read<BattleProvider>().setDiceResult(
          DiceDisplay(
            expression: result.expression,
            rolls: result.rolls,
            modifier: result.modifier,
            total: result.total,
          ),
        );
  }
}
