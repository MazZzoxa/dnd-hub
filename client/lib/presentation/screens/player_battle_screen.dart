import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/battle_action_request_model.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/session_model.dart';
import '../../domain/battle/dice_service.dart';
import '../../domain/providers/battle_provider.dart';
import '../../domain/providers/campaign_provider.dart';
import '../../domain/providers/character_provider.dart';
import '../../domain/providers/session_provider.dart';
import '../widgets/battle_character_card.dart';
import '../widgets/battle_toolbar.dart';
import '../widgets/battle_workspace_widgets.dart';
import '../widgets/dice_roller_sheet.dart';
import 'battle_character_view_screen.dart';

class PlayerBattleScreen extends StatefulWidget {
  final int campaignId;
  final int sessionId;

  const PlayerBattleScreen({
    super.key,
    required this.campaignId,
    required this.sessionId,
  });

  @override
  State<PlayerBattleScreen> createState() => _PlayerBattleScreenState();
}

class _PlayerBattleScreenState extends State<PlayerBattleScreen> {
  final DiceService _dice = DiceService();

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
    final campaigns = context.watch<CampaignProvider>();
    final sessionProvider = context.watch<SessionProvider>();
    final characters = context.watch<CharacterProvider>();
    final battle = context.watch<BattleProvider>();
    final membership = campaigns.currentMembership;

    if (membership == null) {
      return const Scaffold(
        body: Center(child: Text('Участник кампании не найден')),
      );
    }

    final session = _findSession(sessionProvider.sessions, widget.sessionId);
    final ownCharacter = _ownCharacter(membership, characters);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              battle.active?.name.trim().isNotEmpty == true
                  ? '⚔ ${battle.active!.name}'
                  : '⚔ Боевой режим · Игрок',
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
          : _activeBody(battle, membership, ownCharacter, characters.characters),
    );
  }

  SessionModel? _findSession(List<SessionModel> sessions, int id) {
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  CharacterModel? _ownCharacter(
    CampaignMemberModel membership,
    CharacterProvider provider,
  ) {
    final id = membership.linkedCharacterId;
    if (id == null) return null;
    for (final character in provider.characters) {
      if (character.id == id) return character;
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
                  'Боевой режим не активен',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  session == null
                      ? 'Сессия недоступна.'
                      : 'Ожидайте запуска боевого режима от ГМ.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _activeBody(
    BattleProvider provider,
    CampaignMemberModel membership,
    CharacterModel? ownCharacter,
    List<CharacterModel> allCharacters,
  ) {
    final ownSyncId = ownCharacter?.syncId ?? '';
    final currentTurn = provider.currentTurn;
    final currentName = currentTurn == null
        ? ''
        : _nameForSync(currentTurn.characterSyncId, allCharacters);
    final ownTurn =
        ownCharacter != null && provider.isCurrentTurnFor(ownCharacter.syncId);
    final requests = ownCharacter == null
        ? const <BattleActionRequestModel>[]
        : provider.actionRequests
            .where((request) => request.actorCharacterSyncId == ownCharacter.syncId)
            .toList(growable: false);
    final latestRequest = requests.isEmpty ? null : requests.last;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  ownTurn ? Icons.flash_on : Icons.hourglass_empty,
                  color: ownTurn ? AppTheme.primary : AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ownTurn
                        ? '⚔ Ваш ход'
                        : currentTurn == null
                            ? '⏳ Ожидание хода ГМ'
                            : '⏳ Ход: $currentName',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        BattleToolbar(onDice: _rollDice, canEndBattle: false),
        const SizedBox(height: 12),
        if (ownCharacter == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Ваш персонаж ещё не привязан к участнику кампании. Остальные участники доступны только для просмотра.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ),
          )
        else ...[
          if (latestRequest != null)
            _requestStatusCard(latestRequest),
          const SizedBox(height: 10),
          BattleCharacterCard.fromCharacter(
            character: ownCharacter,
            canEdit: false,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => BattleCharacterViewScreen(
                  character: ownCharacter,
                  canAct: ownTurn,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: ownTurn
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BattleCharacterViewScreen(
                          character: ownCharacter,
                          canAct: true,
                        ),
                      ),
                    )
                : null,
            icon: const Icon(Icons.flash_on_outlined),
            label: const Text('Открыть действия'),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            const Icon(Icons.groups_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Группа',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${provider.projections.length}',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final itemWidth = width >= 900 ? (width - 16) / 2 : width;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final projection in provider.projections.values)
                  if (projection.characterSyncId != ownSyncId)
                    SizedBox(
                      width: itemWidth,
                      child: BattleCharacterCard.fromProjection(
                        projection: projection,
                        canEdit: false,
                        onTap: _findCharacter(
                          projection.characterSyncId,
                          allCharacters,
                        ) ==
                            null
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => BattleCharacterViewScreen(
                                      character: _findCharacter(
                                        projection.characterSyncId,
                                        allCharacters,
                                      )!,
                                      canAct: false,
                                    ),
                                  ),
                                ),
                      ),
                    ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        BattleJournalList(
          entries: provider.journal,
          gmDetailed: false,
          characterName: (syncId) => _nameForSync(syncId, allCharacters),
        ),
        if (provider.lastDice != null) ...[
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.casino_outlined),
              title: Text(
                '${provider.lastDice!.expression} = ${provider.lastDice!.total}',
              ),
              subtitle: Text(
                'Броски: ${provider.lastDice!.rolls.join(', ')}',
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _requestStatusCard(BattleActionRequestModel request) {
    final text = switch (request.status) {
      BattleActionRequestStatus.declared => 'Действие объявлено',
      BattleActionRequestStatus.pendingGm => '⏳ Ожидание ГМ',
      BattleActionRequestStatus.approved => '✓ Действие принято',
      BattleActionRequestStatus.modified => '✎ Действие изменено ГМ',
      BattleActionRequestStatus.rejected => '❌ Действие отклонено',
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.flash_on_outlined),
        title: Text(request.actionName),
        subtitle: Text(text),
      ),
    );
  }

  CharacterModel? _findCharacter(
    String syncId,
    List<CharacterModel> characters,
  ) {
    for (final character in characters) {
      if (character.syncId == syncId) return character;
    }
    return null;
  }

  String _nameForSync(String syncId, List<CharacterModel> characters) {
    final character = _findCharacter(syncId, characters);
    return character?.name ?? (syncId.isEmpty ? '—' : syncId);
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
