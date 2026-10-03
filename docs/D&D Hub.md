# 🎲 D&D Hub

## 1. Идея проекта

## Текущее состояние

Текущая версия клиента: `v1.0.0`.

В версии `v0.4.0` реализованы локальные Campaign и GM-инструменты, просмотр персонажей для GM, Session Tools, изображения персонажей в Био и круглых аватарах, а также обновления интерфейса и локального хранения данных.

**D&D Hub** — кроссплатформенное **local-first приложение** для управления персонажами и кампаниями D&D.

Главная задача проекта — заменить бумажный или неудобный электронный лист персонажа на современный интерактивный инструмент, которым удобно пользоваться непосредственно во время игровой сессии.

Приложение должно позволять:

- хранить персонажа;
    
- быстро изменять HP, временные HP, XP, деньги и другие параметры;
    
- управлять инвентарём;
    
- хранить заклинания и способности;
    
- хранить Bio и заметки;
    
- импортировать персонажей и отдельные элементы по PDF, ссылкам и другим форматам;
    
- экспортировать персонажей, предметы, заклинания и другие данные;
    
- создавать собственную локальную библиотеку контента;
    
- переносить библиотеку и другие данные между устройствами;
    
- создавать кампании;
    
- подключать игроков к GM;
    
- синхронизировать данные;
    
- использовать боевой режим.
    

До версии v1.0 проект последовательно развивает основной сценарий использования D&D Hub: персонаж → библиотека → Campaign → GM → локальный сервер и синхронизация → Battle → Session → Gameplay State.

После v1.0 фиксированный roadmap заканчивается. Проект будет развиваться итеративно по мере реального использования приложения. Новые изменения появляются только тогда, когда для них есть практическая причина: найденная ошибка, неудобство, обратная связь, необходимость улучшить существующую функцию или новая идея.

Главный принцип:

> **Сначала качественный основной продукт до v1.0 → затем спокойная итеративная доработка по мере использования и необходимости.**


# 2. Главная концепция

Основная линия разработки до v1.0:

```text
Персонаж
   ↓
Локальное приложение
   ↓
Локальная база данных
   ↓
Импорт / экспорт
   ↓
Локальная библиотека контента
   ↓
Campaign
   ↓
GM / DM
   ↓
Локальный GM Server
   ↓
Real-Time Sync
   ↓
Battle Mode
   ↓
Session Tools
   ↓
Gameplay State
   ↓
v1.0 — Complete Core Product
```

После v1.0 отдельные крупные системы заранее не планируются. Развитие определяется реальным использованием приложения.

---

# 3. Главные цели проекта

## Основная цель

Создать удобный цифровой инструмент для игрока D&D, который позволяет:

- быстро открыть персонажа;
    
- быстро изменить параметры;
    
- быстро найти нужную информацию;
    
- работать без интернета;
    
- хранить данные локально;
    
- переносить данные между устройствами.
    

## Результат v1.0

Создать полноценный инструмент для всей игровой группы:

```text
Player
   ↓
Character
   ↓
Campaign
   ↓
GM
   ↓
Battle
   ↓
Session
   ↓
Gameplay State
```

## Развитие после v1.0

После завершения основной концепции проект не имеет заранее заданного долгосрочного списка функций. Возможные изменения определяются практикой использования приложения.

Приоритет имеют:

- исправление ошибок;
- улучшение удобства и UX;
- повышение стабильности;
- улучшение существующих функций;
- запросы пользователей;
- новые идеи, которые действительно полезны в реальной игре.
    

---

# 4. Главный архитектурный принцип — Local First

Основной принцип:

> **Пользователь должен иметь возможность полноценно пользоваться D&D Hub без обязательного сервера и интернета.**

В первой версии:

```text
┌─────────────────────────────┐
│          D&D Hub            │
│          Flutter            │
│              ↓              │
│        Business Logic       │
│              ↓              │
│        Local Storage        │
│              ↓              │
│            SQLite           │
└─────────────────────────────┘
```

Не требуется:

- удалённый сервер;
    
- облачная база;
    
- обязательный интернет;
    
- аккаунт;
    
- multiplayer;
    
- GM.
    

---

# 5. Локальность данных

Все основные данные пользователя хранятся на его устройстве.

```text
User Device
│
├── Characters
├── Local Content Library
├── Homebrew
├── Imported Content
├── Notes
├── History
└── Settings
```

D&D Hub не должен требовать собственного облачного хранилища для основной работы приложения.

---

# 6. Будущая модель кампании

После появления Campaign сервером становится **компьютер GM**.

```text
                 GM PC
          ┌─────────────────┐
          │    D&D Hub      │
          │   GM + Server   │
          └────────┬────────┘
                   │
             Local Network
                   │
      ┌────────────┼────────────┐
      ↓            ↓            ↓
   Player 1     Player 2     Player 3
    Android       PC          Android
```

GM запускает приложение и создаёт кампанию.

Игроки подключаются к GM для совместной работы и синхронизации.

При этом локальное хранение на устройствах игроков сохраняется.

---

# 7. Платформы

Основные платформы:

```text
Android
Windows
```

В будущем потенциально:

```text
iOS
Linux
macOS
```

Основной сценарий использования — телефон во время игровой сессии.

PC-версия должна использовать ту же модель данных, но иметь более просторный интерфейс.

---

# 8. Технологический стек

## Клиент

```text
Flutter
Dart
```

Flutter используется как единая кодовая база для Android и Windows.

## Локальное хранение

```text
SQLite
```

SQLite используется для хранения:

- персонажей;
    
- предметов;
    
- заклинаний;
    
- способностей;
    
- пользовательского контента;
    
- заметок;
    
- XP;
    
- истории;
    
- настроек;
    
- импортированных данных.
    

## Будущий сервер

Предварительно:

```text
Python
FastAPI
WebSocket
```

Backend появляется только после завершения локального клиента.

---

# 9. Mobile First

Интерфейс в первую очередь проектируется под телефон.

Главные действия должны быть доступны максимально быстро.

Например:

```text
┌─────────────────────┐
│ Character            │
├─────────────────────┤
│ ❤️ HP                │
│ 37 / 42              │
│                     │
│ 🛡 AC     16         │
│ ⚡ Initiative +3     │
│                     │
│ ⭐ Level 5           │
│ ✨ XP 1250           │
│ 💰 Gold 245         │
│                     │
│ 🎒 Inventory    →   │
│ ✨ Spells       →   │
│ ⚔ Abilities     →   │
│ 📝 Notes        →   │
└─────────────────────┘
```

На PC:

```text
┌────────────┬─────────────────────────────┐
│ Navigation │ Character                   │
│            │                             │
│ Overview   │ HP / AC / Initiative        │
│ Inventory  │ Attributes                  │
│ Spells     │ Inventory Preview            │
│ Abilities  │ Recent Activity              │
│ Bio        │                             │
│ Notes      │                             │
└────────────┴─────────────────────────────┘
```

---

# 10. Главные разделы приложения

Основные разделы:

```text
Character
Inventory
Spells
Abilities
Bio
Notes
Library
History
Settings
```

В будущем:

```text
Campaign
GM
Combat
Sessions
World
```

---

# 11. Character

Основная информация:

- имя;
    
- race/species;
    
- класс;
    
- подкласс;
    
- уровень;
    
- background;
    
- XP.
    

## Атрибуты

```text
Strength
Dexterity
Constitution
Intelligence
Wisdom
Charisma
```

## Боевые параметры

```text
HP
Max HP
Temporary HP
Armor Class
Initiative
Speed
Proficiency Bonus
Conditions
```

## Дополнительно

При необходимости добавить:

- saving throws;
    
- skills;
    
- death saves;
    
- другие параметры персонажа.
    

---

# 12. Система опыта

Система XP добавляется в **v0.3**.

Она должна быть полноценной частью модели персонажа.

Возможности:

- хранение текущего XP;
    
- добавление XP;
    
- уменьшение XP;
    
- изменение уровня;
    
- отображение прогресса;
    
- определение следующего уровня;
    
- история изменения XP.
    

Пример:

```text
Level 5

1250 XP
██████████░░░

Next Level
1500 XP
```

Система XP должна быть отдельным модулем, чтобы её можно было изменять независимо от UI.

---

# 13. Быстрые параметры

Параметры, которые часто меняются во время игры, должны изменяться максимально быстро.

## HP

```text
37 / 42

[ Damage ] [ Heal ]
```

или:

```text
[-1] [-5] [-10] [+1] [+5] [+10]
```

## Temporary HP

```text
HP: 30 / 42
Temporary HP: 8
```

## Gold

```text
245 GP

[-] [+]
```

## XP

```text
1250 XP

[-] [+]
```

---

# 14. Inventory

Инвентарь интерактивный.

Пример:

```text
Inventory

Weapons
────────────────
Longsword ×1
Dagger ×2

Armor
────────────────
Chain Mail ×1

Consumables
────────────────
Healing Potion ×3

Other
────────────────
Rope ×1
Torch ×5
```

Предмет может содержать:

- название;
    
- количество;
    
- описание;
    
- вес;
    
- категорию;
    
- стоимость;
    
- свойства;
    
- ссылку на источник;
    
- пользовательские поля;
    
- тип контента.
    

Количество изменяется быстро:

```text
Potion ×3

[-] 3 [+]
```

---

# 15. Spells

Заклинание является отдельным объектом данных.

Поля:

- название;
    
- уровень;
    
- школа;
    
- время применения;
    
- дальность;
    
- компоненты;
    
- длительность;
    
- описание;
    
- дополнительные параметры;
    
- ссылка на источник;
    
- тип контента.
    

Основная задача:

> **пользователь должен быстро найти, открыть и использовать заклинание во время игры.**

---

# 16. Abilities

Хранение:

- классовых способностей;
    
- особенностей species/race;
    
- талантов;
    
- других способностей.
    

Модель:

```text
Ability
├── ID
├── Name
├── Description
├── Category
├── Source
└── Source URL
```

---

# 17. Bio персонажа

В перспективе сделать полноценный профиль персонажа.

```text
Bio
├── Appearance
├── Personality
├── Ideals
├── Bonds
├── Flaws
├── Backstory
└── Other
```

Цель:

> сделать Bio удобным и красивым, а не просто большим текстовым полем.

---

# 18. Notes

Личные заметки игрока.

```text
NPC:
Marcus — торговец

Важно:
Найти старую таверну.

Пароль:
"Красная Луна"
```

В дальнейшем Notes могут превратиться в полноценный журнал кампании.

---

# 19. History

История изменений:

```text
21:43  HP      -12
21:40  Gold    +50
21:32  Potion  -1
21:15  XP      +200
```

History пригодится для:

- восстановления ошибок;
    
- просмотра действий;
    
- анализа сессии;
    
- GM;
    
- синхронизации.
    

---

# 20. Пользовательская библиотека контента

**Встроенная общая база предметов, заклинаний, монстров и других элементов не является обязательной частью D&D Hub.**

Вместо этого пользователь сам формирует свою локальную библиотеку.

```text
Local Content Library
│
├── Spells
├── Items
├── Abilities
├── Monsters
├── Equipment
└── Other
```

Пользователь сам решает, какие данные ему нужны.

---

# 21. Принцип пользовательской библиотеки

Пользователь может:

```text
Create
Import
Edit
Delete
Export
```

любой подходящий объект.

Например:

```text
+ Add Spell

├── Create manually
├── Import from URL
├── Import from PDF
└── Import from file
```

После этого объект сохраняется локально.

---

# 22. Типы контента

Каждый объект должен иметь информацию о происхождении.

Например:

```text
ContentItem
├── type
├── name
├── data
├── sourceType
├── sourceUrl
├── createdAt
└── updatedAt
```

Возможные значения `sourceType`:

```text
USER_CREATED
IMPORTED
LOCAL
```

D&D Hub не обязан иметь глобальную публичную базу всех элементов D&D.

---

# 23. Добавление предметов и заклинаний

Интерфейс должен быть быстрым.

Например:

```text
+ Add Item
```

открывает:

```text
Search / Library

Longsword
Shield
Potion
My Custom Sword
...
```

Для заклинаний:

```text
+ Add Spell
```

```text
Search / Library

Fire Bolt
Shield
Magic Missile
My Custom Spell
...
```

Источник данных — локальная библиотека пользователя.

---

# 24. Импорт персонажа

Главная функция:

```text
Import Character
```

Возможные источники:

```text
PDF
URL
JSON
D&D Hub File
Future Formats
```

Пример:

```text
Import Character

[ Select PDF ]

или

[ Paste URL ]

или

[ Import File ]
```

После импорта:

```text
External Data
 ↓
Importer
 ↓
Parser
 ↓
Validation
 ↓
D&D Hub Character
 ↓
SQLite
```

---

# 25. Импорт по ссылке

Не использовать отдельные кнопки вида:

```text
Import from character sheet
Import from Website X
```

Вместо этого используется универсальная функция:

> **Импортировать по ссылке**

Пользователь вставляет ссылку на:

- персонажа;
    
- предмет;
    
- заклинание;
    
- способность;
    
- другое содержимое.
    

```text
Paste URL
[_____________________]

[Import]
```

Программа пытается определить тип и преобразовать данные во внутреннюю модель D&D Hub.

---

# 26. Импорт PDF

Пользователь может выбрать PDF-файл.

```text
PDF
 ↓
Parser
 ↓
Extract Data
 ↓
Validation
 ↓
Preview
 ↓
Save
```

Перед сохранением желательно показывать пользователю найденные данные, чтобы он мог проверить ошибки импорта.

---

# 27. Импорт отдельных объектов

Импорт должен поддерживать не только персонажа.

```text
Import Character
Import Item
Import Spell
Import Ability
Import Monster
Import Other
```

Например:

```text
URL
 ↓
Detected: Spell
 ↓
Preview
 ↓
Save to Library
```

После этого заклинание можно добавить в персонажа.

---

# 28. Импортированное содержимое хранится локально

После импорта пользователю не нужно каждый раз повторно получать данные.

```text
External Source
       ↓
    Import
       ↓
 Local Library
       ↓
Use many times
```

Например:

```text
Library
├── My Fire Spell
├── Magic Sword
├── Custom Monster
└── Imported Item
```

---

# 29. Ссылки на источники

У импортированного или созданного контента может храниться:

```text
Source URL
```

Например:

```text
Spell
├── Name
├── Data
└── Source URL
```

Пользователь может нажать:

```text
[Open Source]
```

чтобы вернуться к исходной странице.

---

# 30. Экспорт

D&D Hub должен позволять экспортировать пользовательские данные.

## Экспорт персонажа

```text
PDF
JSON
D&D Hub Character File
```

## Экспорт предмета

```text
JSON
D&D Hub File
```

## Экспорт заклинания

```text
JSON
D&D Hub File
```

## Экспорт другого контента

```text
Ability
Monster
Homebrew
Campaign Data
```

---

# 31. Единый формат D&D Hub

Необходимо создать собственный формат данных приложения.

Например:

```text
character.dndhub
item.dndhub
spell.dndhub
library.dndhub
campaign.dndhub
backup.dndhub
```

Это позволит:

- переносить данные;
    
- делать резервные копии;
    
- импортировать данные;
    
- обмениваться пользовательским контентом;
    
- в будущем синхронизировать данные.
    

---

# 32. Перенос локальной библиотеки между устройствами

Это одна из важных функций.

Пользователь может собрать библиотеку на одном устройстве:

```text
PC
 ↓
Local Library
```

затем:

```text
Export Library
 ↓
library.dndhub
 ↓
Phone
 ↓
Import Library
```

После этого все нужные предметы и заклинания доступны на новом устройстве.

---

# 33. Резервное копирование

Необходимо предусмотреть полный backup.

```text
Create Backup
 ↓
dndhub_backup.dndhub
```

Внутри:

```text
Characters
Local Library
Imported Content
Homebrew
Notes
History
Settings
```

Восстановление:

```text
Restore Backup
 ↓
Select File
 ↓
Restore
```

---

# 34. Local Library и персонажи

Библиотека должна быть отделена от конкретного персонажа.

```text
Local Library
      ↓
      ├── Spell
      ├── Item
      └── Ability
             ↓
        Character
```

Один предмет можно использовать несколькими персонажами, не импортируя его повторно.

---

# 35. Campaign

В **v0.3** добавляется система Campaign.

Campaign объединяет:

```text
GM
Players
Characters
```

В дальнейшем:

```text
Campaign
├── Players
├── Characters
├── Sessions
├── Notes
├── Combat
└── World Data
```

---

# 36. Accounts / идентификация игроков

На этапе Campaign необходимо предусмотреть идентификацию участников.

Основная цель:

```text
User
 ↓
Character
 ↓
Campaign
```

При этом аккаунт не должен требовать обязательного облачного сервиса.

---

# 37. GM / DM Mode

В **v0.4** GM получает отдельный интерфейс:

```text
Campaign
│
├── Players
├── Characters
└── Session
```

GM может видеть листы персонажей игроков.

Например:

```text
Kael
Rogue Lv.5
HP 30 / 42
AC 16
Gold 295
```

---

# 38. Локальный GM Server

В **v0.5** появляется локальный сервер. В `v0.5.0` LAN-сценарий завершён: GM запускает временный FastAPI-сервер, Player находит его через локальный UDP discovery и подключается по WebSocket.

GM запускает:

```text
D&D Hub
     ↓
Campaign
     ↓
Host Game
     ↓
Local GM Server
```

Игроки подключаются к GM без обязательного интернета.

Стек v0.5.0:

```text
Python
FastAPI
WebSocket
UDP discovery
```

---

# 39. Real-Time Synchronization

Система синхронизации:

```text
Player
   ↕
Sync Service
   ↕
GM Server
   ↕
Other Clients
```

В `v0.5.0` реализованы:

- transport-independent protocol v2;
- stable `sync_id` отдельно от локальных SQLite ID;
- real-time sync кампании, участников, сессий, персонажей, инвентаря, заклинаний, способностей, атак, заметок, spell slots и XP history;
- acknowledgements, ordered `sequence` и bounded event history;
- authoritative GM Server state;
- initial/recovery snapshots;
- reconnect/resume и snapshot fallback;
- duplicate command protection;
- campaign/entity scope validation;
- automatic Campaign Member registration for joining players;
- persistent local client identity for campaign membership;
- separate GM / Player campaign interfaces;
- role-aware campaign list: owned vs joined campaigns;
- player-side permission boundary: only linked character and its child data can be mutated over the network.

Wi-Fi P2P и Bluetooth остаются будущими transport-опциями. Интернет/VPN transport не входит в текущий LAN-релиз.
    

---

# 40. Локальные данные и синхронизация

Синхронизация не должна заменять локальную базу.

```text
Character
    │
    ├── Local DB
    │
    └── Sync Service
             │
             ↓
          GM Server
```

Основная модель данных остаётся локальной.

---

# 41. Battle Mode

В **v0.6** появляется меню боя.

Цель:

> **сделать основные операции во время боя максимально быстрыми.**

---

# 42. Dice Roller

Необходимые дайсы:

```text
d4
d6
d8
d10
d12
d20
d100
```

Поддержка формул:

```text
1d20 + 5
2d6 + 3
1d8 + 4
```

В дальнейшем можно добавить:

- advantage;
    
- disadvantage;
    
- несколько бросков;
    
- историю бросков.
    

---

# 43. Damage / Healing

Боевой интерфейс должен позволять быстро:

```text
Attack
 ↓
Roll
 ↓
Damage
 ↓
HP
```

Также:

```text
Damage
Heal
Temporary HP
```

---

# 44. Temporary HP в бою

В боевом режиме должны учитываться временные HP.

Например:

```text
HP: 30 / 42
Temporary HP: 8
```

При получении урона система должна корректно учитывать временные HP.

---

# 45. Combat State

В дальнейшем:

```text
Combat
├── Initiative
├── Characters
├── NPC
├── Enemies
├── HP
├── Temporary HP
├── Conditions
├── Round
└── Turn
```

---

# 46. GM Battle Mode

GM получает:

```text
Campaign
 ↓
Session
 ↓
Battle
```

Например:

```text
Round 4

1. Kael       21
2. Goblin     18
3. Mira       15
4. Orc        10
```

GM может:

- управлять инициативой;
    
- менять HP;
    
- применять состояния;
    
- управлять NPC;
    
- управлять противниками;
    
- бросать дайсы;
    
- начинать новый раунд;
    
- переключать ход.
    

---

# 47. Session Tools

После Battle Mode можно добавить инструменты игровой сессии.

```text
Session
├── Notes
├── Events
├── Rewards
├── XP
├── Loot
├── NPC
└── History
```

История персонажа и история кампании могут использоваться совместно.

---

# 48. Экспорт и обмен данными кампании

Экспорт и импорт кампании не являются обязательной частью зафиксированного v1.0 roadmap. Эта возможность может быть рассмотрена только при появлении реальной необходимости во время использования приложения.

Если такая функция будет добавлена, данные конкретных игроков должны оставаться отделёнными от общей информации кампании.

---

# 49. Развитие после v1.0

После v1.0 фиксированный roadmap заканчивается. Отдельные заранее запланированные системы вроде World System, глобальных NPC/Quests, AI Assistant или AI GM не являются частью дальнейшего плана проекта.

D&D Hub будет развиваться постепенно, только когда для этого появляется практическая причина. Основные источники изменений:

- реальные проблемы и баги;
- неудобства, обнаруженные при использовании;
- обратная связь пользователей;
- необходимость улучшить существующий функционал;
- новые идеи, которые вписываются в концепцию приложения.

Новые версии не обязаны следовать заранее определённой последовательности `v1.1 → v1.2 → v1.3`. Номер версии будет отражать фактически выпущенные изменения, а не заранее обещанный набор функций.

> **v1.0 — завершение первоначального roadmap и стабильная база для дальнейшего итеративного развития.**

---

# 50. Версия v0.1 — Local Character

Цель:

> **Полностью рабочий локальный цифровой лист персонажа.**

Функции:

- создание персонажа;
    
- редактирование;
    
- просмотр;
    
- SQLite;
    
- HP;
    
- Max HP;
    
- Temporary HP;
    
- XP как базовое поле;
    
- Level;
    
- Gold;
    
- Attributes;
    
- Inventory;
    
- Spells;
    
- Abilities;
    
- Bio;
    
- Notes;
    
- базовая History.
    

Не делать:

- Campaign;
    
- GM;
    
- сервер;
    
- multiplayer;
    
- синхронизацию;
    
- Battle Mode;
    
- AI;
    
- NPC;
    
- Quests;
    
- World.
    

---

# 51. Версия v0.2 — Import / Export / Local Library

Основная цель:

> **Дать пользователю возможность самому формировать и переносить нужный игровой контент.**

Добавить:

- Local Content Library;
    
- создание предметов;
    
- создание заклинаний;
    
- создание способностей;
    
- импорт PDF;
    
- импорт URL;
    
- импорт JSON;
    
- универсальный Import Manager;
    
- External Content;
    
- source URL;
    
- локальное хранение импортированных данных;
    
- экспорт предметов;
    
- экспорт заклинаний;
    
- экспорт персонажа;
    
- единый формат `.dndhub`;
    
- библиотечный экспорт;
    
- библиотечный импорт;
    
- полный backup.
    

---

# 52. Версия v0.3 — Campaign + XP System

Цель:

> **Перейти от отдельного персонажа к игровой кампании.**

Добавить:

- полноценную систему XP;
    
- определение уровня;
    
- прогресс до следующего уровня;
    
- историю XP;
    
- Campaign;
    
- пользователей;
    
- роли;
    
- GM;
    
- привязку персонажа к кампании;
    
- базовое управление участниками.
    

---

# 53. Версия v0.4 — GM Mode ✅

Добавить:

- GM Dashboard;
    
- список игроков;
    
- список персонажей;
    
- просмотр листов;
    
- информацию о персонажах;
    
- управление кампанией;
    
- базовые Session Tools.
    

---

# 54. Версия v0.5 — Local GM Server + Sync

Статус текущего v0.5.0: **завершён LAN-срез**.

Реализовано:

- FastAPI;
- WebSocket;
- локальный GM Server;
- LAN discovery;
- подключение игроков;
- transport-independent sync protocol v2;
- stable `sync_id`;
- full campaign state sync;
- authoritative state + sequence/history;
- snapshots;
- reconnect / resume;
- snapshot fallback;
- duplicate command protection.

Отложено после LAN-среза v0.5:

- Wi-Fi P2P;
- Bluetooth fallback;
- интернет/VPN transport.

Внутри LAN-среза дополнительно завершены Campaign roles/permissions, автоматическая регистрация подключившихся игроков и разделение GM/Player интерфейсов.
    

---

# 55. Версия v0.6 — Battle Mode

Добавить:

- Dice Roller;
    
- формулы бросков;
    
- инициативу;
    
- урон;
    
- лечение;
    
- Temporary HP;
    
- Conditions;
    
- Round;
    
- Turn;
    
- NPC;
    
- Enemy;
    
- GM Battle Interface.
    

---

# 56. Версия v0.7 — Extended Session Tools

v0.7 превращает Session в рабочее пространство конкретной игровой встречи, не вводя пока отдельную долгоживущую World System.

Реализуемые инструменты:

- Session Journal / отдельные Notes;
- Session Events;
- XP Rewards поверх существующей системы XP;
- Session Loot с последующей выдачей в Inventory;
- единая Session History из Session Events и существующего Combat Journal;
- дополнительные GM-инструменты, необходимые для ведения текущей Session;
- Battle остаётся частью Session и использует существующую Battle-инфраструктуру.

NPC и Quest могут присутствовать внутри Session как временная заметка/событие, но отдельными глобальными сущностями мира в v0.7 не становятся.
    

---

# 57. Версия v1.0 — завершение основной концепции

**v1.0 — не отдельный новый этап, а стабильный результат завершения основной разработки D&D Hub.**

В неё входит весь фундамент:

```text
Character
Inventory
Spells
Abilities
Bio
Notes
XP
History
Local Library
Import
Export
Backup
Campaign
GM
Local GM Server
Real-Time Sync
Battle Mode
Session Tools
```

Главная цель v1.0:

> **Создать полноценный local-first инструмент для игрока и GM, которым реально можно пользоваться во время игровой сессии.**

Фактическая реализация v1.0.0 завершает core gameplay слой проекта:

```text
Gameplay State
├── Life State
├── Conditions
├── GM Grants
└── Custom Battle Actions
```

Игровые изменения со стороны GM проходят через авторитетные команды сервера и отражаются в синхронизируемом Character State, Battle Journal и Session History. Conditions остаются хранимым игровым состоянием без полноценного Rules Engine.

---

# 58. Предварительная архитектура клиента

```text
D&D Hub
│
├── Presentation
│   ├── Screens
│   ├── Widgets
│   ├── Navigation
│   └── Themes
│
├── Domain
│   ├── Character
│   ├── Inventory
│   ├── Spells
│   ├── Abilities
│   ├── Bio
│   ├── Notes
│   ├── XP
│   ├── Combat
│   ├── Campaign
│   ├── Content
│   └── Session
│
├── Data
│   ├── Database
│   ├── Models
│   ├── Repositories
│   └── Storage
│
├── Import
│   ├── PDF
│   ├── URL
│   ├── JSON
│   └── External
│
├── Export
│   ├── PDF
│   ├── JSON
│   └── D&D Hub Format
│
└── Sync
    └── Future
```

---

# 59. Основная модель данных Character

```text
Character
│
├── Identity
│   ├── id
│   ├── name
│   ├── race/species
│   ├── class
│   ├── subclass
│   ├── background
│   └── level
│
├── Attributes
│   ├── strength
│   ├── dexterity
│   ├── constitution
│   ├── intelligence
│   ├── wisdom
│   └── charisma
│
├── Combat
│   ├── hp
│   ├── maxHp
│   ├── temporaryHp
│   ├── armorClass
│   ├── initiative
│   ├── speed
│   ├── proficiencyBonus
│   └── conditions
│
├── Progression
│   ├── xp
│   └── progression data
│
├── Currency
│   ├── copper
│   ├── silver
│   ├── electrum
│   ├── gold
│   └── platinum
│
├── Inventory
│   └── items[]
│
├── Spells
│   └── spells[]
│
├── Abilities
│   └── abilities[]
│
├── Bio
│   ├── appearance
│   ├── personality
│   ├── ideals
│   ├── bonds
│   ├── flaws
│   └── backstory
│
├── Notes
│   └── notes[]
│
└── History
    └── events[]
```

---

# 60. Модель Local Content Library

```text
LocalLibrary
│
├── Items[]
├── Spells[]
├── Abilities[]
├── Monsters[]
├── Equipment[]
└── OtherContent[]
```

Каждый объект:

```text
ContentItem
├── id
├── type
├── name
├── data
├── sourceType
├── sourceUrl
├── createdAt
└── updatedAt
```

---

# 61. Импорт

```text
ImportManager
│
├── PDFImporter
├── URLImporter
├── JSONImporter
├── CharacterSheetRemoteImporter
└── FutureImporter
```

remote sheet service является только **одним из возможных внешних источников**, а внутренняя модель D&D Hub не зависит от него.

---

# 62. Экспорт

```text
ExportManager
│
├── CharacterExporter
├── ItemExporter
├── SpellExporter
├── LibraryExporter
├── CampaignExporter
├── BackupExporter
└── PDFExporter
```

---

# 63. Принцип переноса данных

Главная задача:

> **Пользователь не должен быть привязан к одному устройству.**

Схема:

```text
Device A
   ↓
Export
   ↓
.dndhub
   ↓
Device B
   ↓
Import
```

То же относится к:

- персонажам;
    
- библиотеке;
    
- Homebrew;
    
- импортированным объектам;
    
- backup;
    
- в будущем кампаниям.
    

---

# 64. Принципы разработки

## 1. Local First

Основные функции не должны зависеть от сервера.

## 2. Mobile First

Приложение прежде всего проектируется для использования во время игры на телефоне.

## 3. Данные отдельно от интерфейса

```text
UI
 ↓
Business Logic
 ↓
Repository
 ↓
SQLite
```

## 4. Импорт не зависит от конкретного источника

```text
External Source
 ↓
Importer
 ↓
Internal D&D Hub Model
```

## 5. Экспорт должен быть предусмотрен с самого начала

Пользователь должен иметь возможность забрать свои данные.

## 6. Библиотека принадлежит пользователю

D&D Hub предоставляет инструмент для создания и управления библиотекой, а не обязан предоставлять полную базу всех игровых материалов.

## 7. Локальное хранение — основа

Сервер появляется только тогда, когда возникает необходимость в совместной игре.

## 8. Sync — отдельный слой

Синхронизация не должна ломать локальную работу.

## 9. Версии должны быть рабочими

Каждый этап должен оставлять после себя работоспособный продукт.

---

# 65. Структура репозитория

```text
dnd-hub/
│
├── client/
│   └── Flutter application
│
├── server/
│   └── Future GM server
│
├── docs/
│   ├── architecture
│   ├── database
│   ├── api
│   ├── design
│   └── roadmap
│
├── README.md
├── LICENSE
└── THIRD_PARTY_NOTICES.md
```

На первых этапах:

```text
client/
docs/
```

будут основными каталогами.

---

# 66. Главный roadmap

```text
                         D&D HUB
                            │
                            ▼
              ┌────────────────────────┐
              │        v0.1             │
              │    Local Character     │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │        v0.2             │
              │ Import / Export /      │
              │ Local Library          │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │        v0.3             │
              │ Campaign + XP System   │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │        v0.4             │
              │       GM Mode          │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │        v0.5             │
              │ Local GM Server + Sync │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │        v0.6             │
              │      Battle Mode       │
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │        v0.7             │
              │  Extended Session Tools│
              └────────────┬───────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │        v1.0             │
              │  Complete Core Product │
              └────────────┬───────────┘
                           │
                           ▼
              ┌──────────────────────────────┐
              │       После v1.0             │
              │     Iterative Development    │
              │                              │
              │ • реальные проблемы           │
              │ • удобство использования      │
              │ • обратная связь              │
              │ • необходимость               │
              │ • новые полезные идеи         │
              └──────────────────────────────┘
```

v1.0 является границей первоначального roadmap. После него отдельные крупные системы заранее не планируются.

# 67. Что делать после v1.0

Основной roadmap завершён. На этом этапе не требуется переходить к новой крупной подсистеме только ради продолжения нумерации версий.

Рабочий цикл после v1.0:

```text
Использование приложения
        ↓
Поиск проблем / неудобств / идей
        ↓
Оценка пользы и сложности
        ↓
Небольшое улучшение
        ↓
Тестирование
        ↓
Новая версия
        ↓
Повторение цикла
```

Крупные изменения следует добавлять только тогда, когда они действительно нужны пользователям или улучшают основной сценарий D&D Hub.

# 68. Главная идея проекта

> **D&D Hub — local-first кроссплатформенное приложение для Android и PC, которое превращает лист персонажа D&D в быстрый интерактивный инструмент с локальным хранением, собственной библиотекой пользовательского контента, импортом и экспортом данных, Campaign, GM, локальной синхронизацией, Battle и Session-инструментами.**

v1.0 завершает первоначальную концепцию проекта. Дальше приложение развивается не по заранее написанному roadmap, а по мере использования, необходимости и появления действительно полезных идей.

## v0.3 — Campaigns, participants and XP

Rules frozen for v0.3:
- One character may be linked to multiple campaigns.
- Every campaign has exactly one GM.
- Deleting a campaign deletes only campaign membership rows; linked characters remain.
- XP belongs to the character, while XP changes are stored as transactions.
- Level is derived from XP and is not edited independently in the UI.
- v0.3 remains fully local/offline; later versions add GM, server, sync, battle mode and session tools.

### Реализация v0.3

Схема SQLite поднята до версии 6. Добавлены `campaigns`, `campaign_members` и `xp_transactions`; формат portable backup поднят до v2. Для v0.2 персонажей при миграции уровень нормализуется по накопленному XP без генерации искусственной истории XP.
