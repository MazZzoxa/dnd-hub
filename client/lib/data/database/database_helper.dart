import 'dart:io';

import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Единая точка доступа к локальной SQLite-базе.
///
/// Архитектурный принцип проекта (см. docs/D_D_Hub.md, п.4 и п.31):
///   UI -> Business Logic -> Repository -> SQLite
///
/// Этот класс — самый нижний уровень (SQLite), выше находятся Repository-классы.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _database;

  static const _dbName = 'dnd_hub.db';
  // v2: добавлены поля полного листа персонажа (спасброски, навыки,
  // заклинательная статистика, ролевые поля) + таблицы attacks и spell_slots.
  // v3: добавлено время накладывания заклинаний и порядок способностей.
  // v4: добавлена таблица library_items (Local Content Library, v0.2,
  // см. docs/D&D Hub.md п.20-22) + поле library_item_id в items/spells/
  // abilities — связь копии на листе персонажа с исходным объектом
  // библиотеки (п.34: один объект библиотеки может использоваться
  // несколькими персонажами без повторного импорта).
  // v5: добавлено поле source_url (ссылка на источник/книгу/страницу) в
  // items/spells/abilities — по образцу одноимённого поля library_items,
  // но заполняется отдельно при создании прямо на листе персонажа.
  static const _dbVersion = 5;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// На Windows/Linux/macOS sqflite не работает "из коробки" — нужен FFI-бэкенд.
  /// На Android/iOS используется обычный sqflite.
  Future<Database> _initDatabase() async {
    String path;

    final bool isDesktop =
        !Platform.isAndroid && !Platform.isIOS; // Windows / Linux / macOS

    if (isDesktop) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final Directory dir = await getApplicationDocumentsDirectory();
      final Directory dndHubDir = Directory(join(dir.path, 'DnDHub'));
      if (!await dndHubDir.exists()) {
        await dndHubDir.create(recursive: true);
      }
      path = join(dndHubDir.path, _dbName);
    } else {
      final String dbPath = await getDatabasesPath();
      path = join(dbPath, _dbName);
    }

    return openDatabase(
      path,
      version: _dbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE characters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        race TEXT NOT NULL DEFAULT '',
        class_name TEXT NOT NULL DEFAULT '',
        subclass TEXT NOT NULL DEFAULT '',
        background TEXT NOT NULL DEFAULT '',
        level INTEGER NOT NULL DEFAULT 1,
        alignment TEXT NOT NULL DEFAULT '',
        player_name TEXT NOT NULL DEFAULT '',
        strength INTEGER NOT NULL DEFAULT 10,
        dexterity INTEGER NOT NULL DEFAULT 10,
        constitution INTEGER NOT NULL DEFAULT 10,
        intelligence INTEGER NOT NULL DEFAULT 10,
        wisdom INTEGER NOT NULL DEFAULT 10,
        charisma INTEGER NOT NULL DEFAULT 10,
        hp INTEGER NOT NULL DEFAULT 10,
        max_hp INTEGER NOT NULL DEFAULT 10,
        temporary_hp INTEGER NOT NULL DEFAULT 0,
        armor_class INTEGER NOT NULL DEFAULT 10,
        initiative INTEGER NOT NULL DEFAULT 0,
        speed INTEGER NOT NULL DEFAULT 30,
        proficiency_bonus INTEGER NOT NULL DEFAULT 2,
        inspiration INTEGER NOT NULL DEFAULT 0,
        hit_dice TEXT NOT NULL DEFAULT '',
        death_save_successes INTEGER NOT NULL DEFAULT 0,
        death_save_failures INTEGER NOT NULL DEFAULT 0,
        saving_throw_proficiencies TEXT NOT NULL DEFAULT '[]',
        skill_proficiencies TEXT NOT NULL DEFAULT '[]',
        xp INTEGER NOT NULL DEFAULT 0,
        copper INTEGER NOT NULL DEFAULT 0,
        silver INTEGER NOT NULL DEFAULT 0,
        electrum INTEGER NOT NULL DEFAULT 0,
        gold INTEGER NOT NULL DEFAULT 0,
        platinum INTEGER NOT NULL DEFAULT 0,
        spellcasting_class TEXT NOT NULL DEFAULT '',
        spellcasting_ability TEXT NOT NULL DEFAULT '',
        personality_traits TEXT NOT NULL DEFAULT '',
        ideals TEXT NOT NULL DEFAULT '',
        bonds TEXT NOT NULL DEFAULT '',
        flaws TEXT NOT NULL DEFAULT '',
        proficiencies_languages TEXT NOT NULL DEFAULT '',
        age TEXT NOT NULL DEFAULT '',
        height TEXT NOT NULL DEFAULT '',
        weight TEXT NOT NULL DEFAULT '',
        eyes TEXT NOT NULL DEFAULT '',
        skin TEXT NOT NULL DEFAULT '',
        hair TEXT NOT NULL DEFAULT '',
        backstory TEXT NOT NULL DEFAULT '',
        allies_organizations TEXT NOT NULL DEFAULT '',
        treasure TEXT NOT NULL DEFAULT ''
      )
    ''');

    // Local Content Library (v0.2, см. docs/D&D Hub.md п.20-22, 68).
    // Библиотека отделена от персонажей: объект создаётся/импортируется
    // один раз и затем может переиспользоваться разными персонажами
    // (п.34) — при добавлении на лист персонажа создаётся копия в
    // items/spells/abilities со ссылкой library_item_id на исходник.
    await db.execute('''
      CREATE TABLE library_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        data TEXT NOT NULL DEFAULT '{}',
        source_type TEXT NOT NULL DEFAULT 'USER_CREATED',
        source_url TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_library_items_type ON library_items (type)');
    await db.execute('CREATE INDEX idx_library_items_name ON library_items (name COLLATE NOCASE)');

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        category TEXT NOT NULL DEFAULT 'Other',
        description TEXT NOT NULL DEFAULT '',
        weight REAL NOT NULL DEFAULT 0,
        library_item_id INTEGER,
        source_url TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE,
        FOREIGN KEY (library_item_id) REFERENCES library_items (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE spells (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        level INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL DEFAULT '',
        range TEXT NOT NULL DEFAULT '',
        components TEXT NOT NULL DEFAULT '',
        casting_time TEXT NOT NULL DEFAULT '',
        duration TEXT NOT NULL DEFAULT '',
        description TEXT NOT NULL DEFAULT '',
        prepared INTEGER NOT NULL DEFAULT 0,
        library_item_id INTEGER,
        source_url TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE,
        FOREIGN KEY (library_item_id) REFERENCES library_items (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE abilities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        library_item_id INTEGER,
        source_url TEXT NOT NULL DEFAULT '',
        FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE,
        FOREIGN KEY (library_item_id) REFERENCES library_items (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE attacks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        character_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        attack_bonus TEXT NOT NULL DEFAULT '',
        damage TEXT NOT NULL DEFAULT '',
        sort_order INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE spell_slots (
        character_id INTEGER NOT NULL,
        level INTEGER NOT NULL,
        total INTEGER NOT NULL DEFAULT 0,
        used INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (character_id, level),
        FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Расширяем таблицу characters новыми колонками (см. _onCreate v2).
      const newColumns = <String, String>{
        'alignment': "TEXT NOT NULL DEFAULT ''",
        'player_name': "TEXT NOT NULL DEFAULT ''",
        'inspiration': 'INTEGER NOT NULL DEFAULT 0',
        'hit_dice': "TEXT NOT NULL DEFAULT ''",
        'death_save_successes': 'INTEGER NOT NULL DEFAULT 0',
        'death_save_failures': 'INTEGER NOT NULL DEFAULT 0',
        'saving_throw_proficiencies': "TEXT NOT NULL DEFAULT '[]'",
        'skill_proficiencies': "TEXT NOT NULL DEFAULT '[]'",
        'spellcasting_class': "TEXT NOT NULL DEFAULT ''",
        'spellcasting_ability': "TEXT NOT NULL DEFAULT ''",
        'personality_traits': "TEXT NOT NULL DEFAULT ''",
        'ideals': "TEXT NOT NULL DEFAULT ''",
        'bonds': "TEXT NOT NULL DEFAULT ''",
        'flaws': "TEXT NOT NULL DEFAULT ''",
        'proficiencies_languages': "TEXT NOT NULL DEFAULT ''",
        'age': "TEXT NOT NULL DEFAULT ''",
        'height': "TEXT NOT NULL DEFAULT ''",
        'weight': "TEXT NOT NULL DEFAULT ''",
        'eyes': "TEXT NOT NULL DEFAULT ''",
        'skin': "TEXT NOT NULL DEFAULT ''",
        'hair': "TEXT NOT NULL DEFAULT ''",
        'backstory': "TEXT NOT NULL DEFAULT ''",
        'allies_organizations': "TEXT NOT NULL DEFAULT ''",
        'treasure': "TEXT NOT NULL DEFAULT ''",
      };
      for (final entry in newColumns.entries) {
        await db.execute('ALTER TABLE characters ADD COLUMN ${entry.key} ${entry.value}');
      }

      await db.execute('''
        CREATE TABLE IF NOT EXISTS attacks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          character_id INTEGER NOT NULL,
          name TEXT NOT NULL,
          attack_bonus TEXT NOT NULL DEFAULT '',
          damage TEXT NOT NULL DEFAULT '',
          sort_order INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS spell_slots (
          character_id INTEGER NOT NULL,
          level INTEGER NOT NULL,
          total INTEGER NOT NULL DEFAULT 0,
          used INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (character_id, level),
          FOREIGN KEY (character_id) REFERENCES characters (id) ON DELETE CASCADE
        )
      ''');
    }

    if (oldVersion < 3) {
      await db.execute("ALTER TABLE spells ADD COLUMN casting_time TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE abilities ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0");

      final abilities = await db.query(
        'abilities',
        columns: ['id'],
        orderBy: 'name COLLATE NOCASE',
      );
      await db.transaction((txn) async {
        for (var i = 0; i < abilities.length; i++) {
          await txn.update(
            'abilities',
            {'sort_order': i},
            where: 'id = ?',
            whereArgs: [abilities[i]['id']],
          );
        }
      });
    }

    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS library_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          name TEXT NOT NULL,
          data TEXT NOT NULL DEFAULT '{}',
          source_type TEXT NOT NULL DEFAULT 'USER_CREATED',
          source_url TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_library_items_type ON library_items (type)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_library_items_name ON library_items (name COLLATE NOCASE)',
      );

      // ALTER TABLE ... ADD COLUMN не позволяет добавить FOREIGN KEY так же
      // явно, как в CREATE TABLE, поэтому для апгрейда добавляем обычную
      // nullable-колонку; ссылочная целостность проверяется на уровне
      // репозитория (см. п.34 ТЗ).
      await db.execute('ALTER TABLE items ADD COLUMN library_item_id INTEGER');
      await db.execute('ALTER TABLE spells ADD COLUMN library_item_id INTEGER');
      await db.execute('ALTER TABLE abilities ADD COLUMN library_item_id INTEGER');
    }

    if (oldVersion < 5) {
      await db.execute("ALTER TABLE items ADD COLUMN source_url TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE spells ADD COLUMN source_url TEXT NOT NULL DEFAULT ''");
      await db.execute("ALTER TABLE abilities ADD COLUMN source_url TEXT NOT NULL DEFAULT ''");
    }
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
