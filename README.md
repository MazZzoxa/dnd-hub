# 🎲 D&D Hub

A local-first, cross-platform D&D character and campaign manager built with Flutter — designed for fast, offline use during actual game sessions.

**Status:** `v0.3.0` — campaigns, participants, character linking, XP progression and XP history.  
**Author:** [@MazZzoxa](https://github.com/MazZzoxa)

🇬🇧 [English](#-d-d-hub) · 🇷🇺 [Русский](#-d-d-hub-1)

<p align="center">
  <img src="screenshots/win-overview.png" alt="D&D Hub — desktop overview" width="70%">
</p>

---

## English

### About

D&D Hub replaces the paper (or clunky digital) character sheet with a fast, interactive tool designed to be used *at the table*, during a session — not just between them.

The project follows a **local-first** approach:

- no account is required;
- no server is required;
- no mandatory internet connection;
- character, campaign and progression data are stored locally in SQLite.

The project is intentionally developed in stages: character management → import/export and local content → campaigns → GM tools → synchronization → battle and session tools.

### Features (v0.3)

#### Character management

- Character profile: race, class, subclass, background, alignment, level
- Six core attributes with modifiers
- Combat stats: HP / temp HP, AC, initiative, speed, proficiency bonus
- Quick +/- adjusters for HP, gold and XP
- Inventory: weapons, armor and miscellaneous items
- Spells with per-level spell slots and spell list
- Abilities and attacks
- Bio: appearance, personality traits, ideals, bonds, flaws and backstory
- Freeform notes

#### Import, export and local content

- PDF character sheet import
- URL character sheet import
- JSON import/export
- Portable `.dndhub` data format
- Import preview before applying imported data
- Local content library for items, spells, abilities and other content
- Full local backup / restore

#### Campaigns

- Create and edit campaigns
- One campaign has exactly one GM
- Add and remove campaign participants
- Change participant roles between GM and Player
- Rename participants
- Link a character to a campaign participant
- One character can be linked to multiple campaigns
- Removing a campaign or participant does not delete the linked character

#### XP system

- XP stored directly on the character
- Automatic level calculation from XP
- Progress toward the next level
- Add or subtract XP
- XP change history with transaction records
- XP remains independent from the campaign and can be used across multiple campaigns

#### Platform and UI

- Windows desktop
- Android
- Responsive UI: bottom navigation on phones and side `NavigationRail` on wider screens
- Shared widgets and data model across supported platforms

### Tech stack

- **Client:** Flutter / Dart
- **Local storage:** SQLite (`sqflite` + `sqflite_common_ffi` for desktop)
- **State management:** Provider
- **Import:** PDF/AcroForm analysis, local OCR and URL/HTML extraction
- **Architecture:** layered — `presentation/` → `domain/` → `data/`

The project is structured so that UI, application logic and persistence remain separated as the feature set grows.

### Screenshots

| | Windows | Android |
|---|---|---|
| **Overview** | ![Windows overview](screenshots/win-overview.png) | ![Android overview](screenshots/android-overview.png) |
| **Inventory** | ![Windows inventory](screenshots/win-inventory.png) | ![Android inventory](screenshots/android-inventory.png) |
| **Spells** | ![Windows spells](screenshots/win-spells.png) | ![Android spells](screenshots/android-spells.png) |
| **Abilities** | ![Windows abilities](screenshots/win-abilities.png) | ![Android abilities](screenshots/android-abilities.png) |

<details>
<summary>More screenshots (character list, bio, notes, settings, character form)</summary>

| | Windows | Android |
|---|---|---|
| **Character list** | ![Windows list](screenshots/win-list.png) | ![Android list](screenshots/android-list.png) |
| **Bio** | ![Windows bio](screenshots/win-bio.png) | ![Android bio](screenshots/android-bio.png) |
| **Notes** | ![Windows notes](screenshots/win-notes.png) | ![Android notes](screenshots/android-notes.png) |
| **Settings** | ![Windows settings](screenshots/win-settings.png) | ![Android settings](screenshots/android-settings.png) |
| **New/Edit character** | ![Windows form](screenshots/win-form.png) | ![Android form](screenshots/android-form.png) |

</details>

### v0.2 screenshots

#### Windows

![Windows — character list](screenshots/v0.2/windows/character-list.png)

![Windows — overview](screenshots/v0.2/windows/overview.png)

![Windows — spells](screenshots/v0.2/windows/spells.png)

![Windows — library](screenshots/v0.2/windows/library.png)

#### Android

![Android — character list](screenshots/v0.2/android/character-list.png)

![Android — overview](screenshots/v0.2/android/overview.png)

![Android — spells](screenshots/v0.2/android/spells.png)

![Android — library](screenshots/v0.2/android/library.png)

### Getting started

Requires Flutter SDK `>=3.3.0`.

```bash
git clone https://github.com/MazZzoxa/dnd-hub.git
cd dnd-hub/client

flutter pub get
flutter run -d windows
```

For Android, connect a device or start an emulator and run:

```bash
flutter run
```

Build a release APK:

```bash
flutter build apk --release
```

### Roadmap — English

The project follows a **local-first → library → campaign → GM → sync → battle** progression, so each released stage remains a working product on its own.

| Version | Milestone |
|---|---|
| **v0.1** ✅ | Local character client |
| **v0.2** ✅ | Import / export, local content library, backup / restore |
| **v0.3** ✅ | Campaigns, participants, character linking, XP system |
| v0.4 | GM mode |
| v0.5 | Local GM server + real-time sync |
| v0.6 | Battle mode |
| v0.7 | Session tools |
| v1.0 | Complete core product |
| v1.1+ | World system, AI assistant, AI GM |

Full detailed design document (in Russian): [`docs/D&D Hub.md`](docs/D%26D%20Hub.md).

### License

[MIT](LICENSE) — do whatever you want with it, just keep the license notice.

---

## 🎲 D&D Hub

Кроссплатформенный **local-first** менеджер персонажей и кампаний D&D на Flutter — быстрый офлайн-инструмент для использования прямо во время игровой сессии.

**Статус:** `v0.3.0` — кампании, участники, привязка персонажей, система опыта и история XP.

### О проекте

D&D Hub заменяет бумажный (или неудобный электронный) лист персонажа современным интерактивным инструментом, которым удобно пользоваться прямо за столом во время сессии.

Главный принцип — **local-first**:

- аккаунт не требуется;
- сервер не требуется;
- интернет не обязателен;
- данные персонажей, кампаний и прогрессии хранятся локально в SQLite.

Проект развивается поэтапно: управление персонажем → импорт/экспорт и локальная библиотека → кампании → инструменты GM → синхронизация → боевые и игровые инструменты.

### Возможности (v0.3)

#### Персонажи

- Профиль персонажа: раса, класс, подкласс, предыстория, мировоззрение, уровень
- 6 базовых характеристик с модификаторами
- Боевые параметры: HP / временные HP, КД, инициатива, скорость, бонус мастерства
- Быстрые +/- изменения HP, золота и XP
- Инвентарь: оружие, броня и прочие предметы
- Заклинания с ячейками по уровням и списком заклинаний
- Способности и атаки
- Био: внешность, черты характера, идеалы, привязанности, слабости и предыстория
- Свободные заметки

#### Импорт, экспорт и локальная библиотека

- Импорт персонажей из PDF
- Импорт персонажей по URL
- JSON импорт/экспорт
- Переносимый формат `.dndhub`
- Превью импортируемых данных перед применением
- Локальная библиотека предметов, заклинаний, способностей и другого контента
- Полный локальный backup / restore

#### Кампании

- Создание и редактирование кампаний
- В каждой кампании ровно один GM
- Добавление и удаление участников
- Смена роли GM / Player
- Переименование участников
- Привязка персонажа к участнику кампании
- Один персонаж может участвовать в нескольких кампаниях
- Удаление кампании или участника не удаляет самого персонажа

#### Система опыта

- XP хранится у персонажа
- Уровень автоматически определяется по XP
- Отображение прогресса до следующего уровня
- Добавление и уменьшение XP
- История изменений XP
- Изменения XP сохраняются как отдельные транзакции
- XP не зависит от конкретной кампании и может использоваться в нескольких кампаниях

#### Платформы и интерфейс

- Windows
- Android
- Адаптивный интерфейс: нижняя навигация на телефонах и боковой `NavigationRail` на широких экранах
- Общие виджеты и модель данных для поддерживаемых платформ

### Стек технологий

- **Клиент:** Flutter / Dart
- **Локальное хранилище:** SQLite (`sqflite` + `sqflite_common_ffi` для desktop)
- **State management:** Provider
- **Импорт:** анализ PDF/AcroForm, локальный OCR и извлечение данных из URL/HTML
- **Архитектура:** слоями — `presentation/` → `domain/` → `data/`

### Запуск проекта

Требуется Flutter SDK `>=3.3.0`.

```bash
git clone https://github.com/MazZzoxa/dnd-hub.git
cd dnd-hub/client

flutter pub get
flutter run -d windows
```

Для Android:

```bash
flutter run
```

Сборка release APK:

```bash
flutter build apk --release
```

### Roadmap — Русский

Проект развивается по схеме **локальный клиент → библиотека контента → кампания → GM → синхронизация → боевой режим**, так что на каждом этапе остаётся рабочий продукт.

| Версия | Этап |
|---|---|
| **v0.1** ✅ | Локальный клиент персонажа |
| **v0.2** ✅ | Импорт/экспорт, локальная библиотека контента, backup / restore |
| **v0.3** ✅ | Кампании, участники, привязка персонажей, система XP |
| v0.4 | Режим GM |
| v0.5 | Локальный GM-сервер + синхронизация в реальном времени |
| v0.6 | Боевой режим |
| v0.7 | Инструменты сессии |
| v1.0 | Завершённый базовый продукт |
| v1.1+ | Мир кампании, AI-ассистент, AI GM |

Полный подробный план разработки: [`docs/D&D Hub.md`](docs/D%26D%20Hub.md).

### Лицензия

[MIT](LICENSE) — свободно используйте и модифицируйте, сохраняя уведомление о лицензии.
