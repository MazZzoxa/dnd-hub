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
    if (created == true && mounted) await context.read<CampaignProvider>().loadCampaigns();
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
          if (provider.campaigns.isEmpty) {
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
                    const Text('Создайте локальную кампанию и назначьте GM.'),
                    const SizedBox(height: 18),
                    FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Новая кампания')),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: provider.campaigns.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final campaign = provider.campaigns[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.groups_outlined)),
                  title: Text(campaign.name),
                  subtitle: Text(campaign.description.isEmpty ? 'Локальная кампания' : campaign.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await provider.selectCampaign(campaign);
                    if (!context.mounted) return;
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CampaignHomeScreen()));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Новая кампания')),
    );
  }
}
