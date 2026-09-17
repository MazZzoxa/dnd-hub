import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../widgets/character_avatar.dart';
import '../../data/models/ability_model.dart';
import '../../data/models/character_model.dart';
import '../../data/models/item_model.dart';
import '../../data/models/note_model.dart';
import '../../data/models/spell_model.dart';
import '../../data/repositories/ability_repository.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/note_repository.dart';
import '../../data/repositories/spell_repository.dart';

class GmCharacterSheetScreen extends StatelessWidget {
  final CharacterModel character;

  const GmCharacterSheetScreen({super.key, required this.character});

  @override
  Widget build(BuildContext context) {
    final id = character.id;
    if (id == null) {
      return const Scaffold(body: Center(child: Text('У персонажа нет ID.')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(character.name.isEmpty ? 'Персонаж' : character.name),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: Text('Просмотр GM', style: TextStyle(color: AppTheme.textSecondary))),
          ),
        ],
      ),
      body: FutureBuilder<_SheetData>(
        future: _load(id),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Не удалось загрузить лист: ${snapshot.error}'));
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _HeaderCard(character: character),
              const SizedBox(height: 12),
              _StatsCard(character: character),
              const SizedBox(height: 12),
              _AttributesCard(character: character),
              const SizedBox(height: 12),
              _ReadOnlyListCard(
                title: 'Инвентарь',
                icon: Icons.backpack_outlined,
                items: data.items.map((item) => '${item.name} ×${item.quantity}').toList(),
                emptyText: 'Инвентарь пуст.',
              ),
              const SizedBox(height: 12),
              _SpellCard(spells: data.spells),
              const SizedBox(height: 12),
              _ReadOnlyListCard(
                title: 'Способности',
                icon: Icons.bolt_outlined,
                items: data.abilities.map((ability) => ability.name).toList(),
                emptyText: 'Способностей нет.',
              ),
              const SizedBox(height: 12),
              _BioCard(character: character),
              const SizedBox(height: 12),
              _ReadOnlyListCard(
                title: 'Заметки',
                icon: Icons.notes_outlined,
                items: data.notes.map((note) => note.title.isEmpty ? note.content : note.title).toList(),
                emptyText: 'Заметок нет.',
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Future<_SheetData> _load(int characterId) async {
    final results = await Future.wait<dynamic>([
      InventoryRepository().getForCharacter(characterId),
      SpellRepository().getForCharacter(characterId),
      AbilityRepository().getForCharacter(characterId),
      NoteRepository().getForCharacter(characterId),
    ]);
    return _SheetData(
      items: results[0] as List<ItemModel>,
      spells: results[1] as List<SpellModel>,
      abilities: results[2] as List<AbilityModel>,
      notes: results[3] as List<NoteModel>,
    );
  }
}

class _SheetData {
  final List<ItemModel> items;
  final List<SpellModel> spells;
  final List<AbilityModel> abilities;
  final List<NoteModel> notes;

  const _SheetData({required this.items, required this.spells, required this.abilities, required this.notes});
}

class _HeaderCard extends StatelessWidget {
  final CharacterModel character;
  const _HeaderCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final subtitle = [character.race, character.className, if (character.subclass.isNotEmpty) character.subclass]
        .where((value) => value.isNotEmpty)
        .join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            CharacterAvatar(
              character: character,
              radius: 30,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(character.name.isEmpty ? 'Без имени' : character.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary)),
                ],
                const SizedBox(height: 4),
                Text('Уровень ${character.level} · ${character.playerName.isEmpty ? 'Игрок не указан' : character.playerName}', style: const TextStyle(color: AppTheme.textSecondary)),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsCard extends StatelessWidget {
  final CharacterModel character;
  const _StatsCard({required this.character});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 22,
          runSpacing: 14,
          children: [
            _Stat(label: 'HP', value: '${character.hp}/${character.maxHp}', icon: Icons.favorite_outline),
            _Stat(label: 'Врем. HP', value: '${character.temporaryHp}', icon: Icons.shield_outlined),
            _Stat(label: 'AC', value: '${character.armorClass}', icon: Icons.security_outlined),
            _Stat(label: 'Инициатива', value: '${character.initiative >= 0 ? '+' : ''}${character.initiative}', icon: Icons.flash_on_outlined),
            _Stat(label: 'Скорость', value: '${character.speed}', icon: Icons.directions_run_outlined),
            _Stat(label: 'Бонус владения', value: '+${character.proficiencyBonus}', icon: Icons.stars_outlined),
            _Stat(label: 'XP', value: '${character.xp}', icon: Icons.auto_awesome_outlined),
            _Stat(label: 'Золото', value: '${character.gold} GP', icon: Icons.monetization_on_outlined),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _Stat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 140,
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.accent),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))])),
          ],
        ),
      );
}

class _AttributesCard extends StatelessWidget {
  final CharacterModel character;
  const _AttributesCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final values = {
      'СИЛ': character.strength,
      'ЛОВ': character.dexterity,
      'ТЕЛ': character.constitution,
      'ИНТ': character.intelligence,
      'МДР': character.wisdom,
      'ХАР': character.charisma,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Атрибуты', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [for (final entry in values.entries) _Attribute(label: entry.key, value: entry.value)]),
        ]),
      ),
    );
  }
}

class _Attribute extends StatelessWidget {
  final String label;
  final int value;
  const _Attribute({required this.label, required this.value});

  int get modifier => ((value - 10) / 2).floor();

  @override
  Widget build(BuildContext context) {
    final sign = modifier >= 0 ? '+' : '';
    return Container(
      width: 82,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: AppTheme.surfaceVariant, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)), const SizedBox(height: 4), Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), Text('$sign$modifier', style: const TextStyle(color: AppTheme.accent))]),
    );
  }
}

class _ReadOnlyListCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> items;
  final String emptyText;
  const _ReadOnlyListCard({required this.title, required this.icon, required this.items, required this.emptyText});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(icon, size: 20, color: AppTheme.accent), const SizedBox(width: 8), Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))]),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(emptyText, style: const TextStyle(color: AppTheme.textSecondary))
            else
              ...items.take(20).map((text) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Text('• $text'))),
            if (items.length > 20) Text('И ещё ${items.length - 20}…', style: const TextStyle(color: AppTheme.textSecondary)),
          ]),
        ),
      );
}

class _SpellCard extends StatelessWidget {
  final List<SpellModel> spells;
  const _SpellCard({required this.spells});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.auto_fix_high_outlined, size: 20, color: AppTheme.accent), SizedBox(width: 8), Text('Заклинания', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))]),
          const SizedBox(height: 12),
          if (spells.isEmpty)
            const Text('Заклинаний нет.', style: TextStyle(color: AppTheme.textSecondary))
          else
            ...spells.take(30).map((spell) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(spell.name),
                  subtitle: Text('Уровень ${spell.level == 0 ? '0 (заговор)' : spell.level}${spell.type.isEmpty ? '' : ' · ${spell.type}'}'),
                )),
          if (spells.length > 30) Text('И ещё ${spells.length - 30}…', style: const TextStyle(color: AppTheme.textSecondary)),
        ]),
      ),
    );
  }
}

class _BioCard extends StatelessWidget {
  final CharacterModel character;
  const _BioCard({required this.character});

  @override
  Widget build(BuildContext context) {
    final values = <String, String>{
      'Внешность': character.height.isEmpty && character.weight.isEmpty && character.eyes.isEmpty && character.hair.isEmpty ? '' : [
        if (character.age.isNotEmpty) 'Возраст: ${character.age}',
        if (character.height.isNotEmpty) 'Рост: ${character.height}',
        if (character.weight.isNotEmpty) 'Вес: ${character.weight}',
        if (character.eyes.isNotEmpty) 'Глаза: ${character.eyes}',
        if (character.hair.isNotEmpty) 'Волосы: ${character.hair}',
      ].join(' · '),
      'Характер': character.personalityTraits,
      'Идеалы': character.ideals,
      'Привязанности': character.bonds,
      'Изъяны': character.flaws,
      'Предыстория': character.backstory,
    };
    final visible = values.entries.where((entry) => entry.value.trim().isNotEmpty).toList();
    Uint8List? imageBytes;
    if (character.bioImageBase64.trim().isNotEmpty) {
      try {
        imageBytes = base64Decode(character.bioImageBase64);
      } catch (_) {
        imageBytes = null;
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.person_outline, size: 20, color: AppTheme.accent), SizedBox(width: 8), Text('Био', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700))]),
          const SizedBox(height: 12),
          if (imageBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 180, maxHeight: 360),
                color: AppTheme.surfaceVariant,
                child: Image.memory(
                  imageBytes!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (visible.isEmpty && imageBytes == null)
            const Text('Био пока не заполнено.', style: TextStyle(color: AppTheme.textSecondary))
          else
            ...visible.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(entry.key, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)), const SizedBox(height: 3), Text(entry.value)]))),
        ]),
      ),
    );
  }
}
