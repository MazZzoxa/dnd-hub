import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/character_model.dart';
import '../../../domain/providers/character_provider.dart';

/// Ролевой раздел персонажа: черты характера, идеалы, привязанности,
/// слабости, владения и языки, внешность, предыстория, союзники и
/// организации, сокровища — вторая страница листа персонажа.
///
/// В отличие от боевых параметров это не то, что меняется каждую минуту
/// боя, поэтому здесь используется обычная форма с кнопкой "Сохранить",
/// а не мгновенное сохранение на каждое нажатие клавиши.
class BioSection extends StatefulWidget {
  const BioSection({super.key});

  @override
  State<BioSection> createState() => _BioSectionState();
}

class _BioSectionState extends State<BioSection> {
  int? _initializedForId;

  late TextEditingController _personalityTraits;
  late TextEditingController _ideals;
  late TextEditingController _bonds;
  late TextEditingController _flaws;
  late TextEditingController _proficienciesLanguages;
  late TextEditingController _age;
  late TextEditingController _height;
  late TextEditingController _weight;
  late TextEditingController _eyes;
  late TextEditingController _skin;
  late TextEditingController _hair;
  late TextEditingController _backstory;
  late TextEditingController _alliesOrganizations;
  late TextEditingController _treasure;

  void _initControllers(CharacterModel c) {
    _personalityTraits = TextEditingController(text: c.personalityTraits);
    _ideals = TextEditingController(text: c.ideals);
    _bonds = TextEditingController(text: c.bonds);
    _flaws = TextEditingController(text: c.flaws);
    _proficienciesLanguages = TextEditingController(text: c.proficienciesLanguages);
    _age = TextEditingController(text: c.age);
    _height = TextEditingController(text: c.height);
    _weight = TextEditingController(text: c.weight);
    _eyes = TextEditingController(text: c.eyes);
    _skin = TextEditingController(text: c.skin);
    _hair = TextEditingController(text: c.hair);
    _backstory = TextEditingController(text: c.backstory);
    _alliesOrganizations = TextEditingController(text: c.alliesOrganizations);
    _treasure = TextEditingController(text: c.treasure);
    _initializedForId = c.id;
  }

  Future<void> _pickBioImage(BuildContext context, CharacterModel current) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final Uint8List? bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось прочитать изображение.')),
        );
        return;
      }

      const maxBytes = 8 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Изображение слишком большое. Максимальный размер — 8 МБ.')),
        );
        return;
      }

      await context.read<CharacterProvider>().updateCharacter(
        current.copyWith(bioImageBase64: base64Encode(bytes)),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Изображение добавлено в био.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось добавить изображение: $error')),
      );
    }
  }

  Future<void> _removeBioImage(BuildContext context, CharacterModel current) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить изображение?'),
        content: const Text('Изображение будет удалено из био персонажа.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await context.read<CharacterProvider>().updateCharacter(
      current.copyWith(bioImageBase64: ''),
    );
  }

  Future<void> _save(BuildContext context, CharacterModel current) async {
    final updated = current.copyWith(
      personalityTraits: _personalityTraits.text.trim(),
      ideals: _ideals.text.trim(),
      bonds: _bonds.text.trim(),
      flaws: _flaws.text.trim(),
      proficienciesLanguages: _proficienciesLanguages.text.trim(),
      age: _age.text.trim(),
      height: _height.text.trim(),
      weight: _weight.text.trim(),
      eyes: _eyes.text.trim(),
      skin: _skin.text.trim(),
      hair: _hair.text.trim(),
      backstory: _backstory.text.trim(),
      alliesOrganizations: _alliesOrganizations.text.trim(),
      treasure: _treasure.text.trim(),
    );
    await context.read<CharacterProvider>().updateCharacter(updated);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено'), duration: Duration(seconds: 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final character = context.watch<CharacterProvider>().selected;
    if (character == null) {
      return const Center(child: Text('Персонаж не выбран'));
    }
    if (_initializedForId != character.id) {
      _initControllers(character);
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          children: [
            const _SectionLabel('Изображение персонажа'),
            const SizedBox(height: 10),
            _BioImageCard(
              character: character,
              onPick: () => _pickBioImage(context, character),
              onRemove: character.bioImageBase64.isEmpty
                  ? null
                  : () => _removeBioImage(context, character),
            ),
            const SizedBox(height: 16),
            const _SectionLabel('Внешность'),
            const SizedBox(height: 10),
            _row([_field(_age, 'Возраст'), _field(_height, 'Рост')]),
            _field(_weight, 'Вес'),
            _row([_field(_eyes, 'Глаза'), _field(_skin, 'Кожа')]),
            _field(_hair, 'Волосы'),
            const SizedBox(height: 16),
            const _SectionLabel('Черты характера'),
            const SizedBox(height: 10),
            _field(_personalityTraits, 'Черты характера', maxLines: 3),
            _field(_ideals, 'Идеалы', maxLines: 3),
            _field(_bonds, 'Привязанности', maxLines: 3),
            _field(_flaws, 'Слабости', maxLines: 3),
            const SizedBox(height: 16),
            const _SectionLabel('Владения и языки'),
            const SizedBox(height: 10),
            _field(_proficienciesLanguages, 'Владения и языки', maxLines: 4),
            const SizedBox(height: 16),
            const _SectionLabel('Предыстория'),
            const SizedBox(height: 10),
            _field(_backstory, 'Предыстория персонажа', maxLines: 8),
            const SizedBox(height: 16),
            const _SectionLabel('Союзники и организации'),
            const SizedBox(height: 10),
            _field(_alliesOrganizations, 'Союзники и организации', maxLines: 4),
            const SizedBox(height: 16),
            const _SectionLabel('Сокровища'),
            const SizedBox(height: 10),
            _field(_treasure, 'Сокровища', maxLines: 4),
          ],
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: FloatingActionButton.extended(
            onPressed: () => _save(context, character),
            icon: const Icon(Icons.save),
            label: const Text('Сохранить'),
          ),
        ),
      ],
    );
  }

  Widget _row(List<Widget> children) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _field(TextEditingController controller, String label, {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _BioImageCard extends StatelessWidget {
  final CharacterModel character;
  final VoidCallback onPick;
  final VoidCallback? onRemove;

  const _BioImageCard({
    required this.character,
    required this.onPick,
    required this.onRemove,
  });

  Uint8List? _bytes() {
    if (character.bioImageBase64.trim().isEmpty) return null;
    try {
      return base64Decode(character.bioImageBase64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 260,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: bytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.image_outlined, size: 38, color: AppTheme.textSecondary),
                          const SizedBox(height: 8),
                          const Text('Изображение не добавлено', style: TextStyle(color: AppTheme.textSecondary)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Text('Не удалось отобразить изображение', style: TextStyle(color: AppTheme.textSecondary)),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onPick,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(bytes == null ? 'Добавить изображение' : 'Заменить'),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Удалить изображение',
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: AppTheme.textSecondary));
  }
}
