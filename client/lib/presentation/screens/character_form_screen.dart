import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/character_model.dart';
import '../../domain/providers/character_provider.dart';

/// Экран создания и редактирования персонажа.
/// Если [existing] == null — создаётся новый персонаж, иначе редактируется он.
class CharacterFormScreen extends StatefulWidget {
  final CharacterModel? existing;

  const CharacterFormScreen({super.key, this.existing});

  @override
  State<CharacterFormScreen> createState() => _CharacterFormScreenState();
}

class _CharacterFormScreenState extends State<CharacterFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _race;
  late final TextEditingController _className;
  late final TextEditingController _subclass;
  late final TextEditingController _background;
  late final TextEditingController _level;
  late final TextEditingController _alignment;
  late final TextEditingController _playerName;

  late final TextEditingController _strength;
  late final TextEditingController _dexterity;
  late final TextEditingController _constitution;
  late final TextEditingController _intelligence;
  late final TextEditingController _wisdom;
  late final TextEditingController _charisma;

  late final TextEditingController _maxHp;
  late final TextEditingController _armorClass;
  late final TextEditingController _initiative;
  late final TextEditingController _speed;
  late final TextEditingController _proficiencyBonus;
  late final TextEditingController _hitDice;
  late final TextEditingController _hitDiceTotal;
  String _hitDiceType = 'd8';

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _race = TextEditingController(text: c?.race ?? '');
    _className = TextEditingController(text: c?.className ?? '');
    _subclass = TextEditingController(text: c?.subclass ?? '');
    _background = TextEditingController(text: c?.background ?? '');
    _level = TextEditingController(text: '${c?.level ?? 1}');
    _alignment = TextEditingController(text: c?.alignment ?? '');
    _playerName = TextEditingController(text: c?.playerName ?? '');

    _strength = TextEditingController(text: '${c?.strength ?? 10}');
    _dexterity = TextEditingController(text: '${c?.dexterity ?? 10}');
    _constitution = TextEditingController(text: '${c?.constitution ?? 10}');
    _intelligence = TextEditingController(text: '${c?.intelligence ?? 10}');
    _wisdom = TextEditingController(text: '${c?.wisdom ?? 10}');
    _charisma = TextEditingController(text: '${c?.charisma ?? 10}');

    _maxHp = TextEditingController(text: '${c?.maxHp ?? 10}');
    _armorClass = TextEditingController(text: '${c?.armorClass ?? 10}');
    _initiative = TextEditingController(text: '${c?.initiative ?? 0}');
    _speed = TextEditingController(text: '${c?.speed ?? 30}');
    _proficiencyBonus = TextEditingController(text: '${c?.proficiencyBonus ?? 2}');
    _hitDice = TextEditingController(text: c?.hitDice ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _race, _className, _subclass, _background, _level, _alignment, _playerName,
      _strength, _dexterity, _constitution, _intelligence, _wisdom, _charisma,
      _maxHp, _armorClass, _initiative, _speed, _proficiencyBonus, _hitDice,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, int fallback) => int.tryParse(c.text.trim()) ?? fallback;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<CharacterProvider>();
    final maxHp = _int(_maxHp, 10);

    final character = (widget.existing ?? const CharacterModel(name: '')).copyWith(
      name: _name.text.trim(),
      race: _race.text.trim(),
      className: _className.text.trim(),
      subclass: _subclass.text.trim(),
      background: _background.text.trim(),
      level: _int(_level, 1),
      alignment: _alignment.text.trim(),
      playerName: _playerName.text.trim(),
      strength: _int(_strength, 10),
      dexterity: _int(_dexterity, 10),
      constitution: _int(_constitution, 10),
      intelligence: _int(_intelligence, 10),
      wisdom: _int(_wisdom, 10),
      charisma: _int(_charisma, 10),
      maxHp: maxHp,
      // При создании HP = MaxHP; при редактировании текущее HP не трогаем,
      // если только оно не оказалось больше нового максимума.
      hp: widget.existing == null
          ? maxHp
          : (widget.existing!.hp > maxHp ? maxHp : widget.existing!.hp),
      armorClass: _int(_armorClass, 10),
      initiative: _int(_initiative, 0),
      speed: _int(_speed, 30),
      proficiencyBonus: _int(_proficiencyBonus, 2),
      hitDice: _hitDice.text.trim(),
    );

    if (_isEditing) {
      await provider.updateCharacter(character);
    } else {
      await provider.createCharacter(character);
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Редактировать персонажа' : 'Новый персонаж')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader('Основное'),
            _field(_name, 'Имя', required: true),
            _row([_field(_race, 'Раса'), _field(_className, 'Класс')]),
            _row([_field(_subclass, 'Подкласс'), _field(_level, 'Уровень', numeric: true)]),
            _field(_background, 'Предыстория'),
            _row([_field(_alignment, 'Мировоззрение'), _field(_playerName, 'Имя игрока')]),
            const SizedBox(height: 20),
            _SectionHeader('Характеристики'),
            _row([
              _field(_strength, 'Сила', numeric: true),
              _field(_dexterity, 'Ловкость', numeric: true),
            ]),
            _row([
              _field(_constitution, 'Телосложение', numeric: true),
              _field(_intelligence, 'Интеллект', numeric: true),
            ]),
            _row([
              _field(_wisdom, 'Мудрость', numeric: true),
              _field(_charisma, 'Харизма', numeric: true),
            ]),
            const SizedBox(height: 20),
            _SectionHeader('Боевые параметры'),
            _row([
              _field(_maxHp, 'Максимум хитов', numeric: true),
              _field(_armorClass, 'КД (Класс Доспеха)', numeric: true),
            ]),
            _row([
              _field(_initiative, 'Инициатива', numeric: true),
              _field(_speed, 'Скорость', numeric: true),
            ]),
            _row([
              _field(_proficiencyBonus, 'Бонус мастерства', numeric: true),
              _field(_hitDice, 'Кость хитов (напр. 20к10)'),
            ]),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(_isEditing ? 'Сохранить изменения' : 'Создать персонажа'),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
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

  Widget _field(TextEditingController controller, String label,
      {bool required = false, bool numeric = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        validator: required
            ? (value) => (value == null || value.trim().isEmpty) ? 'Обязательное поле' : null
            : null,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}
