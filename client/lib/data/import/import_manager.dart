import 'dart:convert';
import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../models/ability_model.dart';
import '../models/attack_model.dart';
import '../models/character_model.dart';
import '../models/item_model.dart';
import '../models/library_item_model.dart';
import '../models/note_model.dart';
import '../models/spell_model.dart';
import '../models/spell_slot_model.dart';
import 'models/pdf_import_draft.dart';
import 'pdf/pdf_importer.dart';
import 'url/url_importer.dart';

/// Центральный импортёр переносимых D&D Hub-файлов.
///
/// Центральная точка импорта D&D Hub. JSON/.dndhub используют существующий
/// переносимый формат, а PDF и URL проходят через общий семантический
/// пайплайн (см. [PdfImportDraft], docs/PDF Importer.md, п.6 "Next steps").
class ImportManager {
  static const String schema = 'dnd-hub';
  static const int supportedFormatVersion = 1;

  final DatabaseHelper _db = DatabaseHelper.instance;

  ImportPreview previewBytes(Uint8List bytes) {
    final payload = _decodeAndValidate(bytes);
    return _buildPreview(payload, importAction: (edits) async => _importPayloadWithEdits(payload, edits));
  }

  Future<ImportPreview> previewPdfBytes(Uint8List bytes) async {
    final draft = await PdfImporter().parseAdaptive(bytes);
    return _previewFromDraft(draft, importAction: (edits) async => _importFromDraft(_applyCharacterEdits(draft, edits)));
  }

  Future<ImportResult> importPdfBytes(Uint8List bytes) async {
    final draft = await PdfImporter().parseAdaptive(bytes);
    return _importFromDraft(draft);
  }

  /// Импорт по ссылке (docs/D&D Hub.md, п.25): пользователь вставляет один
  /// URL, а не выбирает источник из списка сайтов. [UrlImporter] сам
  /// определяет, что за этой ссылкой — прямой PDF, JSON-экспорт D&D Hub или
  /// страница/ответ с данными персонажа — и результат обрабатывается тем же
  /// путём, что и остальные форматы импорта.
  Future<ImportPreview> previewUrl(String url) async {
    final result = await UrlImporter().fetch(url);
    return switch (result) {
      UrlJsonResult(:final bytes) => _previewFromJsonBytes(bytes),
      UrlCharacterDraftResult(:final draft) => _previewFromDraft(draft, importAction: (edits) async => _importFromDraft(_applyCharacterEdits(draft, edits))),
      UrlLibraryItemResult(:final item) => _previewFromLibraryItem(item),
    };
  }

  ImportPreview _previewFromJsonBytes(Uint8List bytes) {
    final payload = _decodeAndValidate(bytes);
    return _buildPreview(payload, importAction: (edits) async => _importPayloadWithEdits(payload, edits));
  }

  Future<ImportResult> importUrl(String url) async {
    final result = await UrlImporter().fetch(url);
    return switch (result) {
      UrlJsonResult(:final bytes) => await importBytes(bytes),
      UrlCharacterDraftResult(:final draft) => await _importFromDraft(draft),
      UrlLibraryItemResult(:final item) => await _importLibraryUrlItem(item),
    };
  }

  Future<ImportResult> _importLibraryUrlItem(LibraryItemModel item) async {
    final db = await _db.database;
    final id = await db.insert('library_items', item.toMap());
    return ImportResult(
      exportType: 'libraryItem',
      title: item.name,
      importedLibraryItemIds: [id],
    );
  }

  ImportPreview _previewFromLibraryItem(LibraryItemModel item) {
    final label = switch (item.type) {
      LibraryItemType.item => 'Предмет',
      LibraryItemType.spell => 'Заклинание',
      LibraryItemType.ability => 'Способность',
      LibraryItemType.other => 'Объект',
    };
    return ImportPreview(
      exportType: 'libraryItem',
      title: item.name,
      counts: {label: 1},
      sections: [
        ImportPreviewSection(
          key: 'item',
          title: 'Данные объекта',
          entities: [
            ImportPreviewEntity(
              key: 'item',
              titleFieldKey: 'item.name',
              fields: [
                ImportPreviewField('Название', item.name, key: 'item.name'),
                ImportPreviewField('Тип', item.type.name, key: 'item.type'),
                if (item.sourceUrl.trim().isNotEmpty)
                  ImportPreviewField('URL источника', item.sourceUrl, key: 'item.sourceUrl'),
                ...item.data.entries
                    .where((entry) => entry.value is String || entry.value is num || entry.value is bool)
                    .take(30)
                    .map(
                      (entry) => ImportPreviewField(
                        entry.key,
                        entry.value.toString(),
                        key: 'item.data.${entry.key}',
                        multiline: entry.key.toLowerCase().contains('description') || entry.key.toLowerCase().contains('text'),
                      ),
                    ),
              ],
            ),
          ],
        ),
      ],
      imageUrl: (item.data['imageUrl'] ?? '').toString(),
      importAction: (edits) => _importLibraryItemModelWithEdits(item, edits),
    );
  }

  Future<ImportResult> _importLibraryItemModelWithEdits(
    LibraryItemModel item,
    Map<String, String> edits,
  ) {
    var updated = item.copyWith(
      name: _str(edits, 'item.name', item.name),
      sourceUrl: _str(edits, 'item.sourceUrl', item.sourceUrl),
    );
    final typeText = edits['item.type'];
    if (typeText != null) {
      for (final candidate in LibraryItemType.values) {
        if (candidate.name == typeText) {
          updated = updated.copyWith(type: candidate);
          break;
        }
      }
    }
    final data = Map<String, dynamic>.from(item.data);
    for (final entry in edits.entries) {
      if (entry.key.startsWith('item.data.')) data[entry.key.substring('item.data.'.length)] = entry.value;
    }
    updated = updated.copyWith(data: data, updatedAt: DateTime.now());
    return _importLibraryUrlItem(updated);
  }

  ImportPreview _previewFromDraft(
    PdfImportDraft draft, {
    ImportAction? importAction,
  }) {
    final character = draft.character;
    final details = _characterPreviewFields(character);
    final sections = <ImportPreviewSection>[
      _attackPreviewSection(draft.attacks),
      _spellPreviewSection(draft.spells),
      _itemPreviewSection(draft.items),
    ].where((section) => section.entities.isNotEmpty).toList(growable: false);

    final counts = <String, int>{
      'Атаки': draft.attacks.length,
      'Заклинания': draft.spells.length,
      'Снаряжение': draft.items.length,
    };
    if (draft.fields.isNotEmpty) counts['Распознанные поля'] = draft.fields.length;
    if (draft.warnings.isNotEmpty) counts['Предупреждения'] = draft.warnings.length;

    return ImportPreview(
      exportType: 'character',
      title: character.name.isEmpty ? 'Персонаж' : character.name,
      counts: counts,
      fields: details,
      sections: sections,
      warnings: draft.warnings,
      importAction: importAction,
    );
  }

  List<ImportPreviewField> _characterPreviewFields(CharacterModel character) {
    return <ImportPreviewField>[
      ImportPreviewField('Имя', character.name, key: 'name'),
      ImportPreviewField('Раса', character.race, key: 'race'),
      ImportPreviewField('Класс', character.className, key: 'className'),
      ImportPreviewField('Подкласс', character.subclass, key: 'subclass'),
      ImportPreviewField('Предыстория', character.background, key: 'background'),
      ImportPreviewField('Уровень', '${character.level}', key: 'level'),
      ImportPreviewField('Мировоззрение', character.alignment, key: 'alignment'),
      ImportPreviewField('Игрок', character.playerName, key: 'playerName'),
      ImportPreviewField('HP', '${character.hp}', key: 'hp'),
      ImportPreviewField('Макс. HP', '${character.maxHp}', key: 'maxHp'),
      ImportPreviewField('Временные HP', '${character.temporaryHp}', key: 'temporaryHp'),
      ImportPreviewField('КД', '${character.armorClass}', key: 'armorClass'),
      ImportPreviewField('Инициатива', '${character.initiative}', key: 'initiative'),
      ImportPreviewField('Скорость', '${character.speed}', key: 'speed'),
      ImportPreviewField('Бонус мастерства', '${character.proficiencyBonus}', key: 'proficiencyBonus'),
      ImportPreviewField('Опыт', '${character.xp}', key: 'xp'),
      ImportPreviewField('Золото', '${character.gold}', key: 'gold'),
      ImportPreviewField('Сила', '${character.strength}', key: 'strength'),
      ImportPreviewField('Ловкость', '${character.dexterity}', key: 'dexterity'),
      ImportPreviewField('Телосложение', '${character.constitution}', key: 'constitution'),
      ImportPreviewField('Интеллект', '${character.intelligence}', key: 'intelligence'),
      ImportPreviewField('Мудрость', '${character.wisdom}', key: 'wisdom'),
      ImportPreviewField('Харизма', '${character.charisma}', key: 'charisma'),
    ].where((field) => field.value.trim().isNotEmpty).toList(growable: false);
  }

  ImportPreviewSection _attackPreviewSection(List<AttackModel> attacks) {
    return ImportPreviewSection(
      key: 'attacks',
      title: 'Атаки',
      entities: [
        for (var i = 0; i < attacks.length; i++)
          ImportPreviewEntity(
            key: 'attacks.$i',
            titleFieldKey: 'attacks.$i.name',
            fields: [
              ImportPreviewField('Название', attacks[i].name, key: 'attacks.$i.name'),
              ImportPreviewField('Бонус атаки', attacks[i].attackBonus, key: 'attacks.$i.attackBonus'),
              ImportPreviewField('Урон', attacks[i].damage, key: 'attacks.$i.damage'),
            ],
          ),
      ],
    );
  }

  ImportPreviewSection _spellPreviewSection(List<SpellModel> spells) {
    return ImportPreviewSection(
      key: 'spells',
      title: 'Заклинания',
      entities: [
        for (var i = 0; i < spells.length; i++)
          ImportPreviewEntity(
            key: 'spells.$i',
            titleFieldKey: 'spells.$i.name',
            fields: [
              ImportPreviewField('Название', spells[i].name, key: 'spells.$i.name'),
              ImportPreviewField('Уровень', '${spells[i].level}', key: 'spells.$i.level'),
              ImportPreviewField('Школа', spells[i].type, key: 'spells.$i.type'),
              ImportPreviewField('Дальность', spells[i].range, key: 'spells.$i.range'),
              ImportPreviewField('Компоненты', spells[i].components, key: 'spells.$i.components'),
              ImportPreviewField('Время накладывания', spells[i].castingTime, key: 'spells.$i.castingTime'),
              ImportPreviewField('Длительность', spells[i].duration, key: 'spells.$i.duration'),
              ImportPreviewField('Подготовлено', spells[i].prepared ? 'Да' : 'Нет', key: 'spells.$i.prepared'),
              ImportPreviewField('Описание', spells[i].description, key: 'spells.$i.description', multiline: true),
            ],
          ),
      ],
    );
  }

  ImportPreviewSection _itemPreviewSection(List<ItemModel> items) {
    return ImportPreviewSection(
      key: 'items',
      title: 'Снаряжение',
      entities: [
        for (var i = 0; i < items.length; i++)
          ImportPreviewEntity(
            key: 'items.$i',
            titleFieldKey: 'items.$i.name',
            fields: [
              ImportPreviewField('Название', items[i].name, key: 'items.$i.name'),
              ImportPreviewField('Количество', '${items[i].quantity}', key: 'items.$i.quantity'),
              ImportPreviewField('Категория', items[i].category, key: 'items.$i.category'),
              ImportPreviewField('Вес', '${items[i].weight}', key: 'items.$i.weight'),
              ImportPreviewField('Источник', items[i].sourceUrl, key: 'items.$i.sourceUrl'),
              ImportPreviewField('Описание', items[i].description, key: 'items.$i.description', multiline: true),
            ],
          ),
      ],
    );
  }

  PdfImportDraft _applyCharacterEdits(PdfImportDraft draft, Map<String, String> edits) {
    final updatedAttacks = [
      for (var i = 0; i < draft.attacks.length; i++)
        draft.attacks[i].copyWith(
          name: _str(edits, 'attacks.$i.name', draft.attacks[i].name),
          attackBonus: _str(edits, 'attacks.$i.attackBonus', draft.attacks[i].attackBonus),
          damage: _str(edits, 'attacks.$i.damage', draft.attacks[i].damage),
        ),
    ];
    final updatedSpells = [
      for (var i = 0; i < draft.spells.length; i++)
        draft.spells[i].copyWith(
          name: _str(edits, 'spells.$i.name', draft.spells[i].name),
          level: _int(edits, 'spells.$i.level', draft.spells[i].level),
          type: _str(edits, 'spells.$i.type', draft.spells[i].type),
          range: _str(edits, 'spells.$i.range', draft.spells[i].range),
          components: _str(edits, 'spells.$i.components', draft.spells[i].components),
          castingTime: _str(edits, 'spells.$i.castingTime', draft.spells[i].castingTime),
          duration: _str(edits, 'spells.$i.duration', draft.spells[i].duration),
          description: _str(edits, 'spells.$i.description', draft.spells[i].description),
          prepared: _bool(edits, 'spells.$i.prepared', draft.spells[i].prepared),
        ),
    ];
    final updatedItems = [
      for (var i = 0; i < draft.items.length; i++)
        draft.items[i].copyWith(
          name: _str(edits, 'items.$i.name', draft.items[i].name),
          quantity: _int(edits, 'items.$i.quantity', draft.items[i].quantity),
          category: _str(edits, 'items.$i.category', draft.items[i].category),
          weight: _double(edits, 'items.$i.weight', draft.items[i].weight),
          sourceUrl: _str(edits, 'items.$i.sourceUrl', draft.items[i].sourceUrl),
          description: _str(edits, 'items.$i.description', draft.items[i].description),
        ),
    ];

    return PdfImportDraft(
      character: draft.character.copyWith(
        name: _str(edits, 'name', draft.character.name),
        race: _str(edits, 'race', draft.character.race),
        className: _str(edits, 'className', draft.character.className),
        subclass: _str(edits, 'subclass', draft.character.subclass),
        background: _str(edits, 'background', draft.character.background),
        level: _int(edits, 'level', draft.character.level),
        alignment: _str(edits, 'alignment', draft.character.alignment),
        playerName: _str(edits, 'playerName', draft.character.playerName),
        hp: _int(edits, 'hp', draft.character.hp),
        maxHp: _int(edits, 'maxHp', draft.character.maxHp),
        temporaryHp: _int(edits, 'temporaryHp', draft.character.temporaryHp),
        armorClass: _int(edits, 'armorClass', draft.character.armorClass),
        initiative: _int(edits, 'initiative', draft.character.initiative),
        speed: _int(edits, 'speed', draft.character.speed),
        proficiencyBonus: _int(edits, 'proficiencyBonus', draft.character.proficiencyBonus),
        xp: _int(edits, 'xp', draft.character.xp),
        gold: _int(edits, 'gold', draft.character.gold),
        strength: _int(edits, 'strength', draft.character.strength),
        dexterity: _int(edits, 'dexterity', draft.character.dexterity),
        constitution: _int(edits, 'constitution', draft.character.constitution),
        intelligence: _int(edits, 'intelligence', draft.character.intelligence),
        wisdom: _int(edits, 'wisdom', draft.character.wisdom),
        charisma: _int(edits, 'charisma', draft.character.charisma),
      ),
      attacks: updatedAttacks,
      spells: updatedSpells,
      items: updatedItems,
      fields: draft.fields,
      warnings: draft.warnings,
    );
  }

  String _str(Map<String, String> edits, String key, String fallback) => edits[key] ?? fallback;
  int _int(Map<String, String> edits, String key, int fallback) => int.tryParse(edits[key] ?? '') ?? fallback;
  double _double(Map<String, String> edits, String key, double fallback) => double.tryParse(edits[key] ?? '') ?? fallback;
  bool _bool(Map<String, String> edits, String key, bool fallback) {
    final value = edits[key]?.trim().toLowerCase();
    if (value == 'да' || value == 'true' || value == '1') return true;
    if (value == 'нет' || value == 'false' || value == '0') return false;
    return fallback;
  }

  Future<ImportResult> _importFromDraft(PdfImportDraft draft) async {
    final db = await _db.database;
    return db.transaction((txn) async {
      final characterRow = draft.character.toMap()..remove('id');
      final characterId = await txn.insert('characters', characterRow);

      for (final attack in draft.attacks) {
        final map = attack.toMap()..remove('id');
        map['character_id'] = characterId;
        await txn.insert('attacks', map);
      }

      for (final spell in draft.spells) {
        final map = spell.toMap()..remove('id');
        map['character_id'] = characterId;
        await txn.insert('spells', map);
      }

      for (final item in draft.items) {
        final map = item.toMap()..remove('id');
        map['character_id'] = characterId;
        await txn.insert('items', map);
      }

      return ImportResult(
        exportType: 'character',
        title: draft.character.name,
        importedCharacterId: characterId,
      );
    });
  }

  Future<ImportResult> importBytes(Uint8List bytes) async {
    final payload = _decodeAndValidate(bytes);
    final preview = _buildPreview(payload);
    final exportType = payload['exportType'] as String;

    switch (exportType) {
      case 'character':
        return _importCharacter(payload, preview);
      case 'library':
        return _importLibrary(payload, preview);
      case 'libraryItem':
        return _importLibraryItem(payload, preview);
      case 'backup':
        return _restoreBackup(payload);
      default:
        throw ImportFormatException('Неподдерживаемый тип импорта: $exportType.');
    }
  }

  Map<String, dynamic> _decodeAndValidate(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw const ImportFormatException('Файл пустой.');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const ImportFormatException(
        'Файл не является корректным UTF-8 JSON.',
      );
    }

    if (decoded is! Map) {
      throw const ImportFormatException('Корень файла должен быть JSON-объектом.');
    }

    final payload = Map<String, dynamic>.from(decoded);
    if (payload['schema'] != schema) {
      throw const ImportFormatException(
        'Это не файл D&D Hub: поле schema не совпадает.',
      );
    }

    final version = _asInt(payload['formatVersion']);
    if (version == null) {
      throw const ImportFormatException(
        'В файле отсутствует корректная версия формата.',
      );
    }
    if (version > supportedFormatVersion) {
      throw ImportFormatException(
        'Файл создан более новой версией D&D Hub (формат v$version). '
        'Текущая версия поддерживает максимум v$supportedFormatVersion.',
      );
    }
    if (version < 1) {
      throw const ImportFormatException('Версия формата не поддерживается.');
    }

    final exportType = payload['exportType'];
    if (exportType is! String || exportType.isEmpty) {
      throw const ImportFormatException('В файле не указан exportType.');
    }

    return payload;
  }

  ImportPreview _buildPreview(Map<String, dynamic> payload, {ImportAction? importAction}) {
    final exportType = payload['exportType'] as String;

    switch (exportType) {
      case 'character':
        final character = _asMap(payload['character']);
        final name = (character?['name'] as String?)?.trim();
        if (character == null || name == null || name.isEmpty) {
          throw const ImportFormatException('В файле персонажа отсутствует имя.');
        }
        final model = CharacterModel.fromMap(character);
        final sections = <ImportPreviewSection>[
          _attackPreviewSection(
            [for (final raw in _asList(payload['attacks'])) AttackModel.fromMap({..._normalizeMap(raw), 'character_id': model.id ?? 0})],
          ),
          _spellPreviewSection(
            [for (final raw in _asList(payload['spells'])) SpellModel.fromMap({..._normalizeMap(raw), 'character_id': model.id ?? 0})],
          ),
          _itemPreviewSection(
            [for (final raw in _asList(payload['inventory'])) ItemModel.fromMap({..._normalizeMap(raw), 'character_id': model.id ?? 0})],
          ),
          _abilityPreviewSection(_asList(payload['abilities'])),
          _notePreviewSection(_asList(payload['notes'])),
        ].where((section) => section.entities.isNotEmpty).toList(growable: false);
        return ImportPreview(
          exportType: exportType,
          title: name,
          counts: {
            'Инвентарь': _asList(payload['inventory']).length,
            'Заклинания': _asList(payload['spells']).length,
            'Способности': _asList(payload['abilities']).length,
            'Атаки': _asList(payload['attacks']).length,
            'Заметки': _asList(payload['notes']).length,
            'Объекты библиотеки': _asList(payload['libraryItems']).length,
          },
          fields: _characterPreviewFields(model),
          sections: sections,
          warnings: const [],
          importAction: importAction,
        );
      case 'library':
        final items = _asList(payload['libraryItems']);
        return ImportPreview(
          exportType: exportType,
          title: 'Библиотека D&D Hub',
          counts: {'Объекты': items.length},
          sections: [
            ImportPreviewSection(
              key: 'libraryItems',
              title: 'Объекты библиотеки',
              entities: [
                for (var i = 0; i < items.length && i < 50; i++)
                  _libraryPreviewEntity(items[i], 'libraryItems.$i'),
              ],
            ),
          ],
          importAction: importAction,
        );
      case 'libraryItem':
        final item = _asMap(payload['item']);
        final name = (item?['name'] as String?)?.trim();
        if (item == null || name == null || name.isEmpty) {
          throw const ImportFormatException('В файле объекта библиотеки отсутствует имя.');
        }
        return ImportPreview(
          exportType: exportType,
          title: name,
          counts: {'Объект': 1},
          sections: [
            ImportPreviewSection(
              key: 'item',
              title: 'Данные объекта',
              entities: [_libraryPreviewEntity(item, 'item')],
            ),
          ],
          importAction: importAction,
        );
      case 'backup':
        final data = _asMap(payload['data']);
        if (data == null) {
          throw const ImportFormatException('В backup отсутствует блок data.');
        }
        return ImportPreview(
          exportType: exportType,
          title: 'Резервная копия D&D Hub',
          counts: {
            'Персонажи': _asList(data['characters']).length,
            'Объекты библиотеки': _asList(data['libraryItems']).length,
            'Предметы': _asList(data['items']).length,
            'Заклинания': _asList(data['spells']).length,
            'Способности': _asList(data['abilities']).length,
            'Заметки': _asList(data['notes']).length,
            'Атаки': _asList(data['attacks']).length,
            'Ячейки заклинаний': _asList(data['spellSlots']).length,
          },
          warnings: const [
            'Восстановление полностью заменит текущие локальные данные D&D Hub.',
          ],
          importAction: importAction,
        );
      default:
        throw ImportFormatException('Неподдерживаемый тип импорта: $exportType.');
    }
  }

  ImportPreviewEntity _libraryPreviewEntity(dynamic raw, String prefix) {
    final map = _asMap(raw) ?? const <String, dynamic>{};
    final data = map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : const <String, dynamic>{};
    final fields = <ImportPreviewField>[
      ImportPreviewField('Название', map['name']?.toString() ?? '', key: '$prefix.name'),
      ImportPreviewField('Тип', map['type']?.toString() ?? '', key: '$prefix.type'),
      if ((map['sourceUrl'] ?? '').toString().trim().isNotEmpty)
        ImportPreviewField('URL источника', map['sourceUrl'].toString(), key: '$prefix.sourceUrl'),
      ...data.entries
          .where((entry) => entry.value is String || entry.value is num || entry.value is bool)
          .take(30)
          .map(
            (entry) => ImportPreviewField(
              entry.key,
              entry.value.toString(),
              key: '$prefix.data.${entry.key}',
              multiline: entry.key.toLowerCase().contains('description') || entry.key.toLowerCase().contains('text'),
            ),
          ),
    ];
    return ImportPreviewEntity(
      key: prefix,
      titleFieldKey: '$prefix.name',
      fields: fields,
    );
  }

  ImportPreviewSection _abilityPreviewSection(List<dynamic> rawItems) {
    return ImportPreviewSection(
      key: 'abilities',
      title: 'Способности',
      entities: [
        for (var i = 0; i < rawItems.length; i++)
          (() {
            final map = _normalizeMap(rawItems[i]);
            return ImportPreviewEntity(
              key: 'abilities.$i',
              titleFieldKey: 'abilities.$i.name',
              fields: [
                ImportPreviewField('Название', map['name']?.toString() ?? '', key: 'abilities.$i.name'),
                ImportPreviewField('Источник', map['source']?.toString() ?? '', key: 'abilities.$i.source'),
                ImportPreviewField('URL источника', map['source_url']?.toString() ?? '', key: 'abilities.$i.sourceUrl'),
                ImportPreviewField('Описание', map['description']?.toString() ?? '', key: 'abilities.$i.description', multiline: true),
              ],
            );
          })(),
      ],
    );
  }

  ImportPreviewSection _notePreviewSection(List<dynamic> rawItems) {
    return ImportPreviewSection(
      key: 'notes',
      title: 'Заметки',
      entities: [
        for (var i = 0; i < rawItems.length; i++)
          (() {
            final map = _normalizeMap(rawItems[i]);
            return ImportPreviewEntity(
              key: 'notes.$i',
              titleFieldKey: 'notes.$i.title',
              fields: [
                ImportPreviewField('Заголовок', map['title']?.toString() ?? '', key: 'notes.$i.title'),
                ImportPreviewField('Содержимое', map['content']?.toString() ?? '', key: 'notes.$i.content', multiline: true),
              ],
            );
          })(),
      ],
    );
  }

  Future<ImportResult> _importPayloadWithEdits(
    Map<String, dynamic> payload,
    Map<String, String> edits,
  ) async {
    final copy = jsonDecode(jsonEncode(payload)) as Map<String, dynamic>;
    final exportType = copy['exportType'];
    if (exportType == 'character') {
      final character = _asMap(copy['character']);
      if (character != null) {
        final current = CharacterModel.fromMap(character);
        copy['character'] = current.copyWith(
          name: _str(edits, 'name', current.name),
          race: _str(edits, 'race', current.race),
          className: _str(edits, 'className', current.className),
          subclass: _str(edits, 'subclass', current.subclass),
          background: _str(edits, 'background', current.background),
          level: _int(edits, 'level', current.level),
          alignment: _str(edits, 'alignment', current.alignment),
          playerName: _str(edits, 'playerName', current.playerName),
          hp: _int(edits, 'hp', current.hp),
          maxHp: _int(edits, 'maxHp', current.maxHp),
          temporaryHp: _int(edits, 'temporaryHp', current.temporaryHp),
          armorClass: _int(edits, 'armorClass', current.armorClass),
          initiative: _int(edits, 'initiative', current.initiative),
          speed: _int(edits, 'speed', current.speed),
          proficiencyBonus: _int(edits, 'proficiencyBonus', current.proficiencyBonus),
          xp: _int(edits, 'xp', current.xp),
          gold: _int(edits, 'gold', current.gold),
          strength: _int(edits, 'strength', current.strength),
          dexterity: _int(edits, 'dexterity', current.dexterity),
          constitution: _int(edits, 'constitution', current.constitution),
          intelligence: _int(edits, 'intelligence', current.intelligence),
          wisdom: _int(edits, 'wisdom', current.wisdom),
          charisma: _int(edits, 'charisma', current.charisma),
        ).toMap();
      }
      _applyListEdits(copy, 'attacks', edits, {
        'name': 'name',
        'attackBonus': 'attack_bonus',
        'damage': 'damage',
      });
      _applyListEdits(copy, 'spells', edits, {
        'name': 'name',
        'level': 'level',
        'type': 'type',
        'range': 'range',
        'components': 'components',
        'castingTime': 'casting_time',
        'duration': 'duration',
        'prepared': 'prepared',
        'description': 'description',
      });
      _applyListEdits(copy, 'inventory', edits, {
        'name': 'name',
        'quantity': 'quantity',
        'category': 'category',
        'weight': 'weight',
        'sourceUrl': 'source_url',
        'description': 'description',
      });
      _applyListEdits(copy, 'abilities', edits, {
        'name': 'name',
        'source': 'source',
        'sourceUrl': 'source_url',
        'description': 'description',
      });
      _applyListEdits(copy, 'notes', edits, {
        'title': 'title',
        'content': 'content',
      });
      _applyListEdits(copy, 'libraryItems', edits, {
        'name': 'name',
      });
    } else if (exportType == 'library') {
      _applyListEdits(copy, 'libraryItems', edits, {
        'name': 'name',
        'type': 'type',
        'sourceUrl': 'sourceUrl',
      });
    } else if (exportType == 'libraryItem') {
      final item = _asMap(copy['item']);
      if (item != null) {
        item['name'] = _str(edits, 'item.name', item['name']?.toString() ?? '');
        item['type'] = _str(edits, 'item.type', item['type']?.toString() ?? '');
        item['sourceUrl'] = _str(edits, 'item.sourceUrl', item['sourceUrl']?.toString() ?? '');
        final data = item['data'];
        if (data is Map) {
          final dataMap = Map<String, dynamic>.from(data);
          for (final entry in edits.entries) {
            if (entry.key.startsWith('item.data.')) {
              dataMap[entry.key.substring('item.data.'.length)] = entry.value;
            }
          }
          item['data'] = dataMap;
        }
      }
    }
    return importBytes(Uint8List.fromList(utf8.encode(jsonEncode(copy))));
  }

  void _applyListEdits(
    Map<String, dynamic> copy,
    String payloadKey,
    Map<String, String> edits,
    Map<String, String> fieldMap,
  ) {
    final list = _asList(copy[payloadKey]);
    for (var i = 0; i < list.length; i++) {
      final map = _asMap(list[i]);
      if (map == null) continue;
      for (final entry in fieldMap.entries) {
        final key = '$payloadKey.$i.${entry.key}';
        if (edits.containsKey(key)) {
          final raw = edits[key]!;
          final previous = map[entry.value];
          if (previous is int) {
            map[entry.value] = int.tryParse(raw) ?? previous;
          } else if (previous is double || previous is num) {
            map[entry.value] = double.tryParse(raw) ?? previous;
          } else if (previous is bool) {
            map[entry.value] = _bool(edits, key, previous);
          } else if (entry.key == 'prepared') {
            map[entry.value] = _bool(edits, key, (previous?.toString() == '1' || previous?.toString().toLowerCase() == 'true'));
          } else {
            map[entry.value] = raw;
          }
        }
      }
    }
  }

  Future<ImportResult> _restoreBackup(Map<String, dynamic> payload) async {
    final data = _asMap(payload['data']);
    if (data == null) {
      throw const ImportFormatException('В backup отсутствует блок data.');
    }

    const requiredTables = <String>[
      'characters',
      'libraryItems',
      'items',
      'spells',
      'abilities',
      'notes',
      'attacks',
      'spellSlots',
    ];
    for (final table in requiredTables) {
      final value = data[table];
      if (value != null && value is! List) {
        throw ImportFormatException('Раздел backup "$table" имеет неверный формат.');
      }
    }

    final db = await _db.database;
    await db.transaction((txn) async {
      // Сначала удаляем дочерние записи, чтобы соблюсти foreign keys.
      for (final table in const [
        'spell_slots',
        'attacks',
        'notes',
        'abilities',
        'spells',
        'items',
        'characters',
        'library_items',
      ]) {
        await txn.delete(table);
      }

      await _insertRows(txn, 'library_items', _asList(data['libraryItems']));
      await _insertRows(txn, 'characters', _asList(data['characters']));
      await _insertRows(txn, 'items', _asList(data['items']));
      await _insertRows(txn, 'spells', _asList(data['spells']));
      await _insertRows(txn, 'abilities', _asList(data['abilities']));
      await _insertRows(txn, 'notes', _asList(data['notes']));
      await _insertRows(txn, 'attacks', _asList(data['attacks']));
      await _insertRows(txn, 'spell_slots', _asList(data['spellSlots']));
    });

    return const ImportResult(
      exportType: 'backup',
      title: 'Резервная копия восстановлена',
    );
  }

  Future<void> _insertRows(
    Transaction txn,
    String table,
    List<dynamic> rows,
  ) async {
    for (final raw in rows) {
      final map = _normalizeMap(raw);
      if (map.isEmpty) continue;
      await txn.insert(table, map);
    }
  }

  Future<ImportResult> _importCharacter(
    Map<String, dynamic> payload,
    ImportPreview preview,
  ) async {
    final characterMap = _asMap(payload['character']);
    if (characterMap == null) {
      throw const ImportFormatException('В файле отсутствует блок character.');
    }

    final db = await _db.database;

    return db.transaction((txn) async {
      final character = CharacterModel.fromMap(characterMap);
      final characterRow = character.toMap()..remove('id');
      final newCharacterId = await txn.insert('characters', characterRow);

      final libraryIdMap = <int, int>{};
      for (final raw in _asList(payload['libraryItems'])) {
        final item = _decodeLibraryMap(raw);
        final oldId = _asInt(item['id']);
        final newId = await txn.insert('library_items', _libraryDbMap(item));
        if (oldId != null) libraryIdMap[oldId] = newId;
      }

      for (final raw in _asList(payload['inventory'])) {
        final map = _normalizeMap(raw);
        map['character_id'] = newCharacterId;
        map.remove('id');
        map['library_item_id'] = _remapLibraryId(map['library_item_id'], libraryIdMap);
        final item = ItemModel.fromMap(map);
        await txn.insert('items', item.toMap()..remove('id'));
      }

      for (final raw in _asList(payload['spells'])) {
        final map = _normalizeMap(raw);
        map['character_id'] = newCharacterId;
        map.remove('id');
        map['library_item_id'] = _remapLibraryId(map['library_item_id'], libraryIdMap);
        final spell = SpellModel.fromMap(map);
        await txn.insert('spells', spell.toMap()..remove('id'));
      }

      for (final raw in _asList(payload['abilities'])) {
        final map = _normalizeMap(raw);
        map['character_id'] = newCharacterId;
        map.remove('id');
        map['library_item_id'] = _remapLibraryId(map['library_item_id'], libraryIdMap);
        final ability = AbilityModel.fromMap(map);
        await txn.insert('abilities', ability.toMap()..remove('id'));
      }

      for (final raw in _asList(payload['attacks'])) {
        final map = _normalizeMap(raw);
        map['character_id'] = newCharacterId;
        map.remove('id');
        final attack = AttackModel.fromMap(map);
        await txn.insert('attacks', attack.toMap()..remove('id'));
      }

      for (final raw in _asList(payload['notes'])) {
        final map = _normalizeMap(raw);
        map['character_id'] = newCharacterId;
        map.remove('id');
        final note = NoteModel.fromMap(map);
        await txn.insert('notes', note.toMap()..remove('id'));
      }

      for (final raw in _asList(payload['spellSlots'])) {
        final map = _normalizeMap(raw);
        map['character_id'] = newCharacterId;
        final slot = SpellSlotModel.fromMap(map);
        await txn.insert('spell_slots', slot.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }

      return ImportResult(
        exportType: preview.exportType,
        title: preview.title,
        importedCharacterId: newCharacterId,
        importedLibraryItemIds: libraryIdMap.values.toList(growable: false),
      );
    });
  }

  Future<ImportResult> _importLibrary(
    Map<String, dynamic> payload,
    ImportPreview preview,
  ) async {
    final items = _asList(payload['libraryItems']);
    final db = await _db.database;
    final importedIds = <int>[];

    await db.transaction((txn) async {
      for (final raw in items) {
        final item = _decodeLibraryMap(raw);
        final id = await txn.insert('library_items', _libraryDbMap(item));
        importedIds.add(id);
      }
    });

    return ImportResult(
      exportType: preview.exportType,
      title: preview.title,
      importedLibraryItemIds: importedIds,
    );
  }

  Future<ImportResult> _importLibraryItem(
    Map<String, dynamic> payload,
    ImportPreview preview,
  ) async {
    final itemRaw = _asMap(payload['item']);
    if (itemRaw == null) {
      throw const ImportFormatException('В файле отсутствует блок item.');
    }
    final item = _decodeLibraryMap(itemRaw);
    final db = await _db.database;
    final id = await db.insert('library_items', _libraryDbMap(item));

    return ImportResult(
      exportType: preview.exportType,
      title: preview.title,
      importedLibraryItemIds: [id],
    );
  }

  Map<String, dynamic> _decodeLibraryMap(dynamic raw) {
    final map = _normalizeMap(raw);
    final name = (map['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw const ImportFormatException('Объект библиотеки должен иметь имя.');
    }

    final type = (map['type'] as String?) ?? '';
    if (!LibraryItemType.values.map((e) => e.name).contains(type)) {
      throw ImportFormatException('Неизвестный тип объекта библиотеки: $type.');
    }

    final data = map['data'];
    if (data != null && data is! Map) {
      throw const ImportFormatException(
        'Поле data объекта библиотеки должно быть JSON-объектом.',
      );
    }

    return {
      if (_asInt(map['id']) != null) 'id': _asInt(map['id']),
      'type': type,
      'name': name,
      'data': Map<String, dynamic>.from(data as Map? ?? const {}),
      'sourceType': (map['sourceType'] as String?) ?? 'userCreated',
      'sourceUrl': (map['sourceUrl'] as String?) ?? '',
      'createdAt': _asDateTimeString(map['createdAt']),
      'updatedAt': _asDateTimeString(map['updatedAt']),
    };
  }

  Map<String, dynamic> _libraryDbMap(Map<String, dynamic> item) {
    final sourceType = switch (item['sourceType']) {
      'imported' => 'IMPORTED',
      'local' => 'LOCAL',
      _ => 'USER_CREATED',
    };

    return {
      'type': (item['type'] as String).toUpperCase(),
      'name': item['name'],
      'data': jsonEncode(item['data']),
      'source_type': sourceType,
      'source_url': item['sourceUrl'],
      'created_at': item['createdAt'],
      'updated_at': item['updatedAt'],
    };
  }

  int? _remapLibraryId(dynamic raw, Map<int, int> idMap) {
    final oldId = _asInt(raw);
    if (oldId == null) return null;
    return idMap[oldId];
  }

  Map<String, dynamic> _normalizeMap(dynamic raw) {
    if (raw is! Map) {
      throw const ImportFormatException('Ожидался JSON-объект.');
    }
    return Map<String, dynamic>.from(raw);
  }

  Map<String, dynamic>? _asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  List<dynamic> _asList(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) return raw;
    throw const ImportFormatException('Ожидался JSON-массив.');
  }

  int? _asInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  String _asDateTimeString(dynamic raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return (parsed ?? DateTime.now().toUtc()).toIso8601String();
  }
}

typedef ImportAction = Future<ImportResult> Function(Map<String, String> edits);

class ImportPreview {
  final String exportType;
  final String title;
  final Map<String, int> counts;
  final Map<String, String> summary;
  final List<ImportPreviewField> fields;
  final List<ImportPreviewSection> sections;
  final List<String> warnings;
  final String imageUrl;
  final ImportAction? importAction;

  const ImportPreview({
    required this.exportType,
    required this.title,
    required this.counts,
    this.summary = const {},
    this.fields = const [],
    this.sections = const [],
    this.warnings = const [],
    this.imageUrl = '',
    this.importAction,
  });
}

class ImportPreviewSection {
  final String key;
  final String title;
  final List<ImportPreviewEntity> entities;

  const ImportPreviewSection({
    required this.key,
    required this.title,
    required this.entities,
  });
}

class ImportPreviewEntity {
  final String key;
  final String titleFieldKey;
  final List<ImportPreviewField> fields;

  const ImportPreviewEntity({
    required this.key,
    required this.titleFieldKey,
    required this.fields,
  });
}

class ImportPreviewField {
  final String label;
  final String value;
  final String key;
  final bool multiline;

  const ImportPreviewField(
    this.label,
    this.value, {
    String? key,
    this.multiline = false,
  }) : key = key ?? label;
}

class ImportResult {
  final String exportType;
  final String title;
  final int? importedCharacterId;
  final List<int> importedLibraryItemIds;

  const ImportResult({
    required this.exportType,
    required this.title,
    this.importedCharacterId,
    this.importedLibraryItemIds = const [],
  });
}

class ImportFormatException implements Exception {
  final String message;

  const ImportFormatException(this.message);

  @override
  String toString() => message;
}
