import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/providers/campaign_provider.dart';
import 'campaign_form_screen.dart';
import 'campaign_home_screen.dart';

class CampaignListScreen extends StatefulWidget {
  const CampaignListScreen({super.key});

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CampaignProvider>().loadCampaigns();
    });
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CampaignFormScreen()),
    );
    if (created == true && mounted) {
      await context.read<CampaignProvider>().loadCampaigns();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Кампании')),
      body: Consumer<CampaignProvider>(
        builder: (context, provider, _) {
          if (provider.loading && provider.campaigns.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final hasOwned = provider.ownedCampaigns.isNotEmpty;
          final hasJoined = provider.joinedCampaigns.isNotEmpty;
          if (!hasOwned && !hasJoined) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.groups_2_outlined, size: 56, color: AppTheme.textSecondary),
                    const SizedBox(height: 14),
                    const Text('Кампаний пока нет', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    const Text('Создайте кампанию или подключитесь к игре GM.'),
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Новая кампания')),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: provider.loadCampaigns,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (hasOwned) ...[
                  _SectionTitle(title: 'Созданные мной', icon: Icons.shield_outlined),
                  ...provider.ownedCampaigns.map((campaign) => _CampaignTile(campaign: campaign)),
                ],
                if (hasOwned && hasJoined) const SizedBox(height: 18),
                if (hasJoined) ...[
                  _SectionTitle(title: 'Присоединённые', icon: Icons.person_outline),
                  ...provider.joinedCampaigns.map((campaign) => _CampaignTile(campaign: campaign, joined: true)),
                ],
                const SizedBox(height: 88),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('Новая кампания'),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      );
}

class _CampaignTile extends StatelessWidget {
  final dynamic campaign;
  final bool joined;

  const _CampaignTile({required this.campaign, this.joined = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(joined ? Icons.person_outline : Icons.shield_outlined),
        ),
        title: Text(campaign.name),
        subtitle: Text(
          campaign.description.isEmpty
              ? (joined ? 'Кампания GM • режим игрока' : 'Ваша кампания • режим GM')
              : campaign.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(joined ? Icons.visibility_outlined : Icons.chevron_right),
        onTap: () async {
          final provider = context.read<CampaignProvider>();
          await provider.selectCampaign(campaign);
          if (!context.mounted) return;
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CampaignHomeScreen()));
        },
      ),
    );
  }
}
