import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/providers/campaign_provider.dart';

class CharacterCampaignsCard extends StatefulWidget {
  final int characterId;
  const CharacterCampaignsCard({super.key, required this.characterId});

  @override
  State<CharacterCampaignsCard> createState() => _CharacterCampaignsCardState();
}

class _CharacterCampaignsCardState extends State<CharacterCampaignsCard> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CampaignProvider>().membershipsForCharacter(widget.characterId);
  }

  @override
  void didUpdateWidget(covariant CharacterCampaignsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.characterId != widget.characterId) {
      _future = context.read<CampaignProvider>().membershipsForCharacter(widget.characterId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final memberships = snapshot.data ?? const <Map<String, dynamic>>[];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: Padding(padding: EdgeInsets.all(14), child: LinearProgressIndicator()));
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Кампании', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (memberships.isEmpty)
                const Text('Персонаж пока не привязан к кампании.', style: TextStyle(color: AppTheme.textSecondary))
              else
                ...memberships.map((membership) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.groups_outlined),
                      title: Text(membership['campaign_name']?.toString() ?? ''),
                      subtitle: Text('${membership['member_name'] ?? ''} · ${membership['role'] == 'gm' ? 'GM' : 'Player'}', style: const TextStyle(color: AppTheme.textSecondary)),
                    )),
            ]),
          ),
        );
      },
    );
  }
}
