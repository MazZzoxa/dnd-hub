# 🎲 D&D Hub

A local-first, cross-platform D&D character manager built with Flutter — a fast, offline digital character sheet for use during actual game sessions.

**Status:** early WIP, `v0.1` — local character client (see [Roadmap](#roadmap--english)).
**Author:** [@MazZzoxa](https://github.com/MazZzoxa)

🇬🇧 [English](#-dd-hub) · 🇷🇺 [Русский](#-dd-hub-1)

<p align="center">
  <img src="screenshots/win-overview.png" alt="D&D Hub — desktop overview" width="70%">
</p>

---

## English

### About

D&D Hub replaces the paper (or clunky digital) character sheet with a fast, interactive tool designed to be used *at the table*, during a session — not just between them.

Core principle: **local-first**. No account, no server, no mandatory internet connection. All character data lives on the device in a local SQLite database. Cloud sync and multiplayer (Campaign/GM mode) are planned for later versions, layered on top of a solid offline foundation — not required to use the app.

### Features (v0.1)

- Character profile: race, class, subclass, background, alignment, level
- Six core attributes with modifiers
- Combat stats: HP / temp HP, AC, initiative, speed, proficiency bonus
- Quick +/- adjusters for HP, gold, XP — the things that change constantly mid-session
- Inventory (weapons, armor, misc items)
- Spells with per-level spell slots and a spell list
- Abilities & attacks
- Bio (appearance, personality traits, ideals, bonds, flaws, backstory)
- Freeform notes
- Responsive UI: bottom navigation on phones, side `NavigationRail` on wide/desktop screens — same widgets, same data, no duplicated logic

### Tech stack

- **Client:** Flutter / Dart
- **Local storage:** SQLite (`sqflite` + `sqflite_common_ffi` for Windows)
- **State management:** Provider
- **Architecture:** layered — `presentation/` (screens, widgets) → `domain/` (providers) → `data/` (repositories, models, database)

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

### Getting started

Requires Flutter SDK `>=3.3.0`.

```bash
cd client
flutter pub get
flutter run -d windows   # or: flutter run -d chrome / an Android device / emulator
```

### Roadmap — English

The project follows a **local-first → library → campaign → GM → sync → battle** progression, so every released version stays a working product on its own.

| Version | Milestone |
|---|---|
| **v0.1** ✅ | Local character client (this release) |
| v0.2 | Import / export, local content library |
| v0.3 | Campaigns, full XP system |
| v0.4 | GM mode |
| v0.5 | Local GM server + real-time sync |
| v0.6 | Battle mode |
| v0.7 | Session tools |
| v1.0 | Complete core product |
| v1.1+ | World system, AI assistant, AI GM |

Full detailed design document (in Russian): [`docs/D&D Hub.md`](docs/D&D%20Hub.md).

### License

[MIT](LICENSE) — do whatever you want with it, just keep the license notice.

---

## 🎲 D&D Hub

Кроссплатформенный **local-first** менеджер персонажей D&D на Flutter — быстрый офлайн цифровой лист персонажа для использования прямо во время игровой сессии.

**Статус:** ранняя разработка, `v0.1` — локальный клиент персонажа (см. [Roadmap](#roadmap--русский)).

### О проекте

D&D Hub заменяет бумажный (или неудобный электронный) лист персонажа современным интерактивным инструментом, которым удобно пользоваться прямо за столом во время сессии.

Главный принцип — **local-first**: без аккаунта, без сервера, без обязательного интернета. Все данные персонажа хранятся локально в SQLite. Синхронизация и совместная игра (Campaign/GM) запланированы на будущие версии поверх надёжного офлайн-фундамента, а не как обязательное требование.

### Возможности (v0.1)

- Профиль персонажа: раса, класс, подкласс, предыстория, мировоззрение, уровень
- 6 базовых характеристик с модификаторами
- Боевые параметры: HP / временные HP, КД, инициатива, скорость, бонус мастерства
- Быстрые +/- регуляторы для HP, золота, опыта — того, что меняется чаще всего во время игры
- Инвентарь (оружие, броня, прочие предметы)
- Заклинания с ячейками по уровням и списком известных
- Способности и атаки
- Био (внешность, черты характера, идеалы, привязанности, слабости, предыстория)
- Свободные заметки
- Адаптивный интерфейс: нижняя навигация на телефоне, боковая `NavigationRail` на широких/десктопных экранах — одни и те же виджеты и данные, без дублирования логики

### Стек технологий

- **Клиент:** Flutter / Dart
- **Локальное хранилище:** SQLite (`sqflite` + `sqflite_common_ffi` для Windows)
- **State management:** Provider
- **Архитектура:** слоями — `presentation/` (экраны, виджеты) → `domain/` (providers) → `data/` (repositories, models, database)

### Скриншоты

См. таблицы со скриншотами выше — они одинаковы для обеих версий README.

### Запуск проекта

Требуется Flutter SDK `>=3.3.0`.

```bash
cd client
flutter pub get
flutter run -d windows   # или: flutter run -d chrome / устройство Android
```

### Roadmap — Русский

Проект развивается по схеме **локальный клиент → библиотека контента → кампания → GM → синхронизация → боевой режим**, так что на каждом этапе остаётся рабочий продукт.

| Версия | Этап |
|---|---|
| **v0.1** ✅ | Локальный клиент персонажа (текущий релиз) |
| v0.2 | Импорт/экспорт, локальная библиотека контента |
| v0.3 | Кампании, полноценная система опыта |
| v0.4 | Режим GM |
| v0.5 | Локальный GM-сервер + синхронизация в реальном времени |
| v0.6 | Боевой режим |
| v0.7 | Инструменты сессии |
| v1.0 | Завершённый базовый продукт |
| v1.1+ | Мир кампании, AI-ассистент, AI GM |

Полный подробный план разработки: [`docs/D&D Hub.md`](docs/D&D%20Hub.md).

### Лицензия

[MIT](LICENSE) — свободно используйте и модифицируйте, сохраняя уведомление о лицензии.
