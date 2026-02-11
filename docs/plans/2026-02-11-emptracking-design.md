# EmpTracking — Design Document

Автоматический тайм-трекер для macOS. Отслеживает активное приложение и заголовок окна, записывает время в SQLite. Аналог Timing.app.

## Ключевые решения

- **Менюбар-приложение** (NSStatusItem + NSPopover), без иконки в доке
- **Опрос каждые 5 секунд** — активное приложение + заголовок окна
- **SQLite** для хранения данных
- **Простой таймлайн-лог** (не дашборд) на первом этапе
- **Не в песочнице** (App Sandbox отключен) — нужен Accessibility API для заголовков окон

## Архитектура

### Компоненты

- **AppDelegate** — точка входа. Создаёт NSStatusItem в менюбаре, по клику открывает popover с таймлайном.
- **ActivityTracker** — сервис с Timer (5 сек). Опрашивает `NSWorkspace.shared.frontmostApplication` для имени приложения и Accessibility API (`AXUIElementCopyAttributeValue` с `kAXFocusedWindowAttribute` + `kAXTitleAttribute`) для заголовка окна.
- **IdleStateMonitor** — подписывается на системные уведомления (сон, блокировка, скринсейвер и т.д.) и управляет флагом `isUserAway`.
- **PowerAssertionChecker** — проверяет `IOPMCopyAssertionsByProcess()` для определения, воспроизводит ли активное приложение медиа.
- **DatabaseManager** — обёртка над SQLite. Запись, чтение, создание таблиц.
- **TimelineViewController** — NSTableView в popover, показывает лог за сегодня.

### Логика записи

Каждые 5 секунд:

1. Проверяем `isUserAway` (блокировка/сон/скринсейвер) — если да, ничего не записываем.
2. Получаем активное приложение и заголовок окна.
3. Проверяем idle: `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: CGEventType(rawValue: ~0)!)` > 120 секунд?
   - Да — проверяем `IOPMCopyAssertionsByProcess()`: активное приложение держит `PreventUserIdleDisplaySleep`?
     - Да (видео/презентация) — пользователь не idle, записываем как обычно.
     - Нет — пользователь idle, закрываем текущую запись, создаём запись с `is_idle = 1`.
   - Нет — пользователь активен.
4. Если `app_bundle_id` + `window_title` совпадают с последней записью — обновляем `end_time`.
5. Если изменились — создаём новую запись.

## Idle и Away

### Idle (2 мин без ввода)

Используем `CGEventSource.secondsSinceLastEventType` для определения времени без ввода. Перед пометкой idle проверяем power assertions активного приложения — если оно воспроизводит медиа, idle не ставим.

### Away (системные события)

Единый флаг `isUserAway`. Первое событие ставит паузу, последующие игнорируются (дедупликация).

| Событие | API | Notification Center |
|---|---|---|
| Экран заблокирован | `com.apple.screenIsLocked` | DistributedNotificationCenter |
| Экран разблокирован | `com.apple.screenIsUnlocked` | DistributedNotificationCenter |
| Скринсейвер вкл | `com.apple.screensaver.didstart` | DistributedNotificationCenter |
| Скринсейвер выкл | `com.apple.screensaver.didstop` | DistributedNotificationCenter |
| Mac засыпает | `NSWorkspace.willSleepNotification` | NSWorkspace.shared.notificationCenter |
| Mac проснулся | `NSWorkspace.didWakeNotification` | NSWorkspace.shared.notificationCenter |
| Дисплей выключился | `NSWorkspace.screensDidSleepNotification` | NSWorkspace.shared.notificationCenter |
| Дисплей включился | `NSWorkspace.screensDidWakeNotification` | NSWorkspace.shared.notificationCenter |
| Сессия неактивна | `NSWorkspace.sessionDidResignActiveNotification` | NSWorkspace.shared.notificationCenter |
| Сессия активна | `NSWorkspace.sessionDidBecomeActiveNotification` | NSWorkspace.shared.notificationCenter |

### Типичные цепочки событий

- **Закрытие крышки:** `screensDidSleep` → `screenIsLocked` → `willSleep` ... `didWake` → `screensDidWake` → `screenIsUnlocked`
- **Cmd+Ctrl+Q:** `screenIsLocked`
- **Скринсейвер → блокировка:** `screensaver.didstart` → `screenIsLocked` ... `screenIsUnlocked` → `screensaver.didstop`

## Модель данных

### Таблица `apps`

| Колонка | Тип | Описание |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Автоинкремент |
| `bundle_id` | TEXT UNIQUE | "com.apple.Safari" |
| `app_name` | TEXT NOT NULL | "Safari" |
| `icon` | BLOB | PNG-данные иконки приложения |

### Таблица `activity_logs`

| Колонка | Тип | Описание |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Автоинкремент |
| `app_id` | INTEGER REFERENCES apps(id) | Ссылка на приложение |
| `window_title` | TEXT | Заголовок окна |
| `start_time` | REAL NOT NULL | Unix timestamp начала |
| `end_time` | REAL NOT NULL | Unix timestamp конца (обновляется каждые 5 сек) |
| `is_idle` | INTEGER DEFAULT 0 | 1 = пользователь отошёл |

### Расположение базы

`~/Library/Application Support/EmpTracking/tracking.db`

## UI

### Менюбар

- `NSStatusItem` с иконкой часов/таймера.
- По клику — `NSPopover` размером ~400x500 pt.

### Popover (таймлайн)

- Заголовок: сегодняшняя дата + общее активное время за день.
- `NSTableView` — список записей за сегодня, от новых к старым.
- Каждая строка:
  ```
  [иконка]  Safari — YouTube — Название видео
  09:15 – 09:47  (32 мин)
  ```
- Idle-записи отображаются серым: `Idle — 10:30 – 10:45 (15 мин)`
- Иконка приложения из таблицы `apps`.

## Запуск и разрешения

### Accessibility

При первом запуске вызываем `AXIsProcessTrustedWithOptions` с промптом. Пока разрешение не выдано — записываем имя приложения без заголовка окна, показываем подсказку в popover.

### Автозапуск

`SMAppService.mainApp.register()` (macOS 13+). Спрашиваем пользователя при первом запуске.

### Info.plist

- `LSUIElement = true` — скрыть из дока
- `NSAccessibilityUsageDescription` — описание для системного диалога

## Структура файлов

```
EmpTracking/
├── AppDelegate.swift              — NSStatusItem, popover, автозапуск
├── Services/
│   ├── ActivityTracker.swift      — Timer, опрос активного окна, idle-логика
│   ├── IdleStateMonitor.swift     — Подписка на системные уведомления
│   ├── PowerAssertionChecker.swift — Проверка power assertions (IOKit)
│   └── DatabaseManager.swift      — SQLite: CRUD, создание таблиц
├── Models/
│   ├── ActivityLog.swift          — Структура записи лога
│   └── AppInfo.swift              — Структура приложения (имя, bundle_id, иконка)
├── Views/
│   ├── TimelineViewController.swift — NSTableView с логами в popover
│   └── TimelineCellView.swift     — Ячейка: иконка + название + время
└── Resources/
    └── Assets.xcassets            — Иконка для менюбара
```

## Ключевые API

| Задача | API |
|---|---|
| Активное приложение | `NSWorkspace.shared.frontmostApplication` |
| Заголовок окна | `AXUIElementCopyAttributeValue` (Accessibility API) |
| Idle time | `CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType:)` |
| Power assertions | `IOPMCopyAssertionsByProcess()` (IOKit) |
| Проверка Accessibility | `AXIsProcessTrustedWithOptions()` |
| Автозапуск | `SMAppService.mainApp.register()` |
| Системные события | `NSWorkspace.shared.notificationCenter` + `DistributedNotificationCenter` |
