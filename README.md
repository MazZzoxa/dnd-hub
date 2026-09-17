# 🎲 D&D Hub

A local-first, cross-platform D&D character manager built with Flutter — a fast, offline digital character sheet for use during actual game sessions.

**Current version:** `v0.4.0`  
**Status:** Local-first character, campaign and GM tools are implemented. Real-time synchronization and the local GM server are planned for `v0.5`.  
**Author:** [@MazZzoxa](https://github.com/MazZzoxa)

🇬🇧 [English](#-dd-hub) · 🇷🇺 [Русский](#-dd-hub-1)

<p align="center">
  <img src="screenshots/win-overview.png" alt="D&D Hub — desktop overview" width="70%">
</p>

---

## 🎲 D&D Hub

### About

D&D Hub is a local-first digital D&D character manager designed to be used directly during a game session.

The main principle is **local-first**: no account, no server and no mandatory Internet connection are required. Character, campaign and progression data are stored locally in SQLite. Multiplayer synchronization and the GM server are deliberately kept for a later stage of the project.

### Features — v0.4.0

**Character management**

- Character profile: race, class, subclass, background, alignment and level
- Six core attributes with modifiers
- Combat stats: HP, temporary HP, AC, initiative, speed and proficiency bonus
- Quick +/- controls for HP, gold and XP
- Inventory: weapons, armor and miscellaneous items
- Spells with spell slots by level
- Abilities and attacks
- Freeform notes
- Bio with appearance, personality traits, ideals, bonds, flaws, backstory and character image
- Circular character avatars using the Bio image while preserving image proportions and quality

**Import / export and local library**

- PDF, URL and JSON import through a shared Import Manager
- Editable import preview before confirming imported data
- Local Content Library for items, spells, abilities and other content
- `.dndhub` character export/import
- Full local backup / restore
- XP history is preserved during character export/import

**Campaigns and GM Mode**

- Campaign creation and management
- Player membership and character linking
- GM Dashboard for a selected campaign
- Player/character overview with HP, AC and initiative
- Read-only character sheet viewer for the GM
- Local Session Tools with an active session, GM notes and session history

**Interface**

- Responsive Flutter UI
- Bottom navigation on phones
- Side `NavigationRail` on wide/desktop screens
- Shared widgets and data across platforms without duplicated business logic
- Primary orange buttons use white text and icons

### Tech stack

- **Client:** Flutter / Dart
- **Local storage:** SQLite (`sqflite` + `sqflite_common_ffi` for Windows/Linux/macOS)
- **State management:** Provider
- **Architecture:** layered — `presentation/` → `domain/` → `data/`

### Screenshots

| | Windows | Android |
|---|---|---|
| **Overview** | ![Windows overview](screenshots/win-overview.png) | ![Android overview](screenshots/android-overview.png) |
| **Inventory** | ![Windows inventory](screenshots/win-inventory.png) | ![Android inventory](screenshots/android-inventory.png) |
| **Spells** | ![Windows spells](screenshots/win-spells.png) | ![Android spells](screenshots/android-spells.png) |
| **Abilities** | ![Windows abilities](screenshots/win-abilities.png) | ![Android abilities](screenshots/android-abilities.png) |

<details>
<summary>More screenshots</summary>

| | Windows | Android |
|---|---|---|
| **Character list** | ![Windows list](screenshots/win-list.png) | ![Android list](screenshots/android-list.png) |
| **Bio** | ![Windows bio](screenshots/win-bio.png) | ![Android bio](screenshots/android-bio.png) |
| **Notes** | ![Windows notes](screenshots/win-notes.png) | ![Android notes](screenshots/android-notes.png) |
| **Settings** | ![Windows settings](screenshots/win-settings.png) | ![Android settings](screenshots/android-settings.png) |
| **New/Edit character** | ![Windows form](screenshots/win-form.png) | ![Android form](screenshots/android-form.png) |

</details>

### Getting started

Requires Flutter SDK `>=3.3.0`.

```bash
cd client
flutter pub get
flutter run -d windows
```

Other targets can be used with the standard Flutter commands, for example an Android device/emulator or Chrome.

### Building

Windows debug build:

```bash
cd client
flutter build windows --debug
```

Android release APK:

```bash
cd client
flutter build apk --release
```

Build artifacts such as `client/build/` and Dart tool caches are ignored by Git.

### Project structure

```text
client/
├── lib/
│   ├── core/            # Theme and shared application infrastructure
│   ├── data/            # SQLite, repositories, models, import/export
│   ├── domain/          # Providers and application logic
│   └── presentation/   # Screens and reusable widgets
├── test/                # Unit and widget tests
├── assets/              # Application assets
└── pubspec.yaml

docs/
├── D&D Hub.md           # Full project plan and architecture notes
├── PDF Importer.md      # PDF importer documentation
```

### Roadmap

The project follows a **local-first → library → campaign → GM → sync → battle** progression.

| Version | Milestone |
|---|---|
| **v0.1** ✅ | Local character client |
| **v0.2** ✅ | Import/export, local content library, backup/restore |
| **v0.3** ✅ | Campaigns, participants, character linking, XP system |
| **v0.3.1** ✅ | Android migration, backup/restore and import fixes |
| **v0.4** ✅ | GM Mode, GM character viewer and local Session Tools |
| v0.5 | Local GM server + real-time synchronization |
| v0.6 | Battle Mode |
| v0.7 | Extended session/gameplay tools |
| v1.0 | Complete core product |
| v1.1+ | World system, AI assistant, AI GM |

Full detailed design document: [`docs/D&D Hub.md`](docs/D%26D%20Hub.md).

### Contributing

Issues and pull requests are welcome. Please keep changes consistent with the local-first architecture and the project plan in `docs/`.

### License

[MIT](LICENSE) — use and modify the project freely while keeping the license notice.

---

## 🇷🇺 Русский

### О проекте

D&D Hub — кроссплатформенный **local-first** менеджер персонажей D&D на Flutter, рассчитанный на использование прямо во время игровой сессии.

Главный принцип — **local-first**: аккаунт, сервер и обязательное подключение к Интернету не требуются. Данные персонажей, кампаний и прогрессии хранятся локально в SQLite. Сервер GM и синхронизация в реальном времени запланированы на следующие этапы.

### Возможности — v0.4.0

**Персонажи**

- Профиль персонажа: раса, класс, подкласс, предыстория, мировоззрение и уровень
- 6 базовых характеристик с модификаторами
- Боевые параметры: HP, временные HP, КД, инициатива, скорость и бонус мастерства
- Быстрые +/- регуляторы для HP, золота и XP
- Инвентарь: оружие, броня и прочие предметы
- Заклинания и ячейки заклинаний по уровням
- Способности и атаки
- Свободные заметки
- Био с внешностью, чертами характера, идеалами, привязанностями, слабостями, предысторией и изображением персонажа
- Круглый аватар персонажа на основе изображения из Био с сохранением пропорций и качества

**Импорт, экспорт и библиотека**

- Импорт PDF, URL и JSON через общий Import Manager
- Редактируемое превью импортируемых данных перед подтверждением импорта
- Локальная библиотека контента для предметов, заклинаний, способностей и других объектов
- Экспорт/импорт персонажа в `.dndhub`
- Полный локальный backup/restore
- История XP сохраняется при экспорте/импорте персонажа

**Кампании и GM Mode**

- Создание и управление кампаниями
- Участники и привязка персонажей
- GM Dashboard для выбранной кампании
- Обзор игроков и персонажей с HP, КД и инициативой
- Лист персонажа в режиме просмотра для GM
- Локальные инструменты сессии: активная сессия, заметки GM и история сессий

**Интерфейс**

- Адаптивный Flutter-интерфейс
- Нижняя навигация на телефонах
- Боковая `NavigationRail` на широких/десктопных экранах
- Общие виджеты и данные для разных платформ
- Основные оранжевые кнопки используют белый текст и иконки

### Запуск проекта

Требуется Flutter SDK `>=3.3.0`.

```bash
cd client
flutter pub get
flutter run -d windows
```

Для других платформ используются стандартные команды Flutter.

### Сборка

Windows:

```bash
cd client
flutter build windows --debug
```

Android APK:

```bash
cd client
flutter build apk --release
```

Файлы сборки и кэши Flutter/Dart исключены из Git через `.gitignore`.

### Структура проекта

```text
client/
├── lib/
│   ├── core/            # Тема и общая инфраструктура
│   ├── data/            # SQLite, repositories, models, import/export
│   ├── domain/          # Providers и логика приложения
│   └── presentation/   # Экраны и переиспользуемые виджеты
├── test/                # Unit/widget tests
├── assets/              # Ресурсы приложения
└── pubspec.yaml

docs/
├── D&D Hub.md           # Полный план и архитектурные заметки проекта
├── PDF Importer.md      # Документация PDF-импортёра
```

### Roadmap

Проект развивается по схеме **локальный клиент → библиотека → кампания → GM → синхронизация → бой**.

| Версия | Этап |
|---|---|
| **v0.1** ✅ | Локальный клиент персонажа |
| **v0.2** ✅ | Импорт/экспорт, локальная библиотека, backup/restore |
| **v0.3** ✅ | Кампании, участники, привязка персонажей, система XP |
| **v0.3.1** ✅ | Исправления Android, backup/restore и импорта |
| **v0.4** ✅ | GM Mode, просмотр персонажей и локальные Session Tools |
| v0.5 | Локальный GM-сервер + синхронизация в реальном времени |
| v0.6 | Боевой режим |
| v0.7 | Расширенные инструменты сессии/игрового процесса |
| v1.0 | Завершённый базовый продукт |
| v1.1+ | Мир кампании, AI-ассистент, AI GM |

Полный подробный план разработки: [`docs/D&D Hub.md`](docs/D%26D%20Hub.md).

### Лицензия

[MIT](LICENSE) — проект можно свободно использовать и изменять с сохранением уведомления о лицензии.
