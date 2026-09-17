import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/character_avatar.dart';
import '../../data/models/campaign_member_model.dart';
import '../../data/models/character_model.dart';
import '../../domain/providers/campaign_provider.dart';
import '../../domain/providers/character_provider.dart';
import 'gm_dashboard_screen.dart';

class CampaignHomeScreen extends StatelessWidget {
  const CampaignHomeScreen({super.key});

  Future<void> _addPlayer(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Добавить участника'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Имя')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Добавить')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    try {
      await context.read<CampaignProvider>().addPlayer(name);
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _editCampaign(BuildContext context, CampaignProvider provider) async {
    final campaign = provider.selected;
    if (campaign == null) return;
    final name = TextEditingController(text: campaign.name);
    final description = TextEditingController(text: campaign.description);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Редактировать кампанию'),
        content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')), const SizedBox(height: 12), TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Описание'))])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () async { try { await provider.saveCampaign(name: name.text, description: description.text); if (context.mounted) Navigator.pop(context); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); } }, child: const Text('Сохранить')),
        ],
      ),
    );
    name.dispose();
    description.dispose();
  }

  Future<void> _delete(BuildContext context) async {
    final provider = context.read<CampaignProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить кампанию?'),
        content: const Text('Кампания и её участники будут удалены. Персонажи и их XP останутся в базе и будут отвязаны от кампании.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))],
      ),
    );
    if (ok == true) {
      await provider.deleteSelected();
      if (context.mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CampaignProvider, CharacterProvider>(
      builder: (context, campaigns, characters, _) {
        final campaign = campaigns.selected;
        if (campaign == null) return const Scaffold(body: Center(child: Text('Кампания не выбрана')));
        return Scaffold(
          appBar: AppBar(
            title: Text(campaign.name),
            actions: [
              IconButton(
                tooltip: 'Режим GM',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GmDashboardScreen()),
                ),
                icon: const Icon(Icons.shield_outlined),
              ),
              IconButton(onPressed: () => _editCampaign(context, campaigns), icon: const Icon(Icons.edit_outlined)),
              IconButton(onPressed: () => _delete(context), icon: const Icon(Icons.delete_outline)),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (campaign.description.isNotEmpty) ...[
                Text(campaign.description, style: const TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 20),
              ],
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shield_outlined, color: AppTheme.primary),
                  title: const Text('GM Dashboard'),
                  subtitle: const Text('Игроки, персонажи и текущая игровая сессия'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const GmDashboardScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [const Text('Участники', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)), const Spacer(), Text('${campaigns.members.length}'), const SizedBox(width: 10), IconButton(onPressed: () => _addPlayer(context), icon: const Icon(Icons.person_add_alt_1_outlined))]),
              const SizedBox(height: 10),
              ...campaigns.members.map((member) => _MemberCard(member: member, characters: characters.characters)),
            ],
          ),
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  final CampaignMemberModel member;
  final List<CharacterModel> characters;
  const _MemberCard({required this.member, required this.characters});

  CharacterModel? _findCharacter(List<CharacterModel> list, int id) {
    for (final character in list) {
      if (character.id == id) return character;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final linked = member.linkedCharacterId == null ? null : _findCharacter(characters, member.linkedCharacterId!);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        child: Row(
          children: [
            linked == null || member.role == CampaignRole.gm
                ? CircleAvatar(
                    child: Icon(member.role == CampaignRole.gm
                        ? Icons.shield_outlined
                        : Icons.person_outline),
                  )
                : CharacterAvatar(character: linked, radius: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(member.name, style: const TextStyle(fontWeight: FontWeight.w700)), Text('${member.role.label}${linked == null ? '' : ' · ${linked.name}'}', style: const TextStyle(color: AppTheme.textSecondary))])),
            PopupMenuButton<String>(
              onSelected: (action) async {
                final provider = context.read<CampaignProvider>();
                try {
                  if (action == 'role') {
                    if (member.role == CampaignRole.gm) {
                      final others = provider.members.where((m) => m.id != member.id).toList();
                      if (others.isEmpty) throw StateError('Добавьте нового участника, чтобы назначить нового GM.');
                      final selected = await showDialog<int>(context: context, builder: (_) => SimpleDialog(title: const Text('Новый GM'), children: [for (final item in others) SimpleDialogOption(onPressed: () => Navigator.pop(context, item.id), child: Text(item.name))]));
                      if (selected != null) await provider.replaceGm(selected);
                    } else {
                      await provider.replaceGm(member.id!);
                    }
                  } else if (action == 'rename') {
                    final controller = TextEditingController(text: member.name);
                    final name = await showDialog<String>(context: context, builder: (_) => AlertDialog(title: const Text('Переименовать участника'), content: TextField(controller: controller, autofocus: true), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Сохранить'))]));
                    controller.dispose();
                    if (name != null && name.trim().isNotEmpty) await provider.saveMember(member.copyWith(name: name));
                  } else if (action == 'link') {
                    final selected = await showDialog<int?>(context: context, builder: (_) => _CharacterPicker(characters: characters, currentId: member.linkedCharacterId));
                    if (selected != null) await provider.linkCharacter(member, selected == -1 ? null : selected);
                  } else if (action == 'delete') {
                    if (await _confirmDelete(context, member)) await provider.removeMember(member);
                  }
                } catch (error) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Переименовать')),
                PopupMenuItem(value: 'role', child: Text('Сменить GM / Player')),
                PopupMenuItem(value: 'link', child: Text('Привязать персонажа')),
                PopupMenuItem(value: 'delete', child: Text('Удалить участника')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, CampaignMemberModel member) async {
    return await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Удалить участника?'), content: Text('Удалить ${member.name} из кампании? Персонаж останется в приложении.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить'))])) ?? false;
  }
}

class _CharacterPicker extends StatelessWidget {
  final List<CharacterModel> characters;
  final int? currentId;
  const _CharacterPicker({required this.characters, required this.currentId});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Персонаж'),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(context, -1), child: const Text('Отвязать')),
        for (final character in characters) SimpleDialogOption(onPressed: () => Navigator.pop(context, character.id), child: Text('${character.name} · ур. ${character.level}')),
      ],
    );
  }
}
