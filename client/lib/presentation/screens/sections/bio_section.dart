import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/character_model.dart';
import '../../../domain/providers/character_provider.dart';

/// Ролевой раздел персонажа: черты характера, идеалы, привязанности,
/// слабости, владения и языки, внешность, предыстория, союзники и
/// организации, сокровища — вторая страница листа Aternia.
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
