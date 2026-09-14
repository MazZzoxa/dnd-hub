import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/providers/campaign_provider.dart';

class CampaignFormScreen extends StatefulWidget {
  const CampaignFormScreen({super.key});

  @override
  State<CampaignFormScreen> createState() => _CampaignFormScreenState();
}

class _CampaignFormScreenState extends State<CampaignFormScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _gm = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _gm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _gm.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Название кампании и имя GM обязательны.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<CampaignProvider>().createCampaign(
            name: _name.text,
            description: _description.text,
            gmName: _gm.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая кампания')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 14),
          TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Описание')),
          const SizedBox(height: 14),
          TextField(controller: _gm, decoration: const InputDecoration(labelText: 'Имя GM')),
          const SizedBox(height: 22),
          FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Создание…' : 'Создать кампанию')),
        ],
      ),
    );
  }
}
