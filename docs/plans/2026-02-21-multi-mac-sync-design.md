# Multi-Mac Sync — Дизайн

## Контекст

EmpTracking работает на одном маке с локальной SQLite БД. Нужна возможность запускать трекер на двух маках (Mac Mini M1 + MacBook) и иметь единую базу для корректных отчётов.

## Решение

Offline-first архитектура с локальным сервером на Mac Mini.

## Архитектура

```
┌─────────────┐         HTTP (LAN)        ┌──────────────────┐
│  MacBook     │ ──────────────────────►  │  Mac Mini M1      │
│  EmpTracking │ ◄──────────────────────  │  Vapor Server     │
│  + локальный │    push/pull activity    │  + SQLite (master)│
│    SQLite    │                           │                   │
└─────────────┘                           └──────────────────┘
                                                   ▲
┌─────────────┐         HTTP (LAN)                 │
│  Mac Mini    │ ──────────────────────────────────┘
│  EmpTracking │    localhost:8080
│  + локальный │
│    SQLite    │
└─────────────┘
```

**Принципы:**
- Каждый Mac пишет в локальный SQLite — работает без сервера
- Сервер на Mac Mini — единая "правда", собирает данные со всех устройств
- Клиенты периодически пушат новые записи и подтягивают чужие
- Сервер доступен по `macmini.local:8080` (mDNS) или статическому IP
- Если сервер недоступен (ноутбук вне сети) — записи копятся локально, синхронизируются при возвращении

## Модель данных (сервер)

### Таблица `devices`

```sql
CREATE TABLE devices (
    id        TEXT PRIMARY KEY,   -- UUID, генерируется при первом запуске
    name      TEXT NOT NULL,      -- имя компьютера ("MacBook Pro", "Mac Mini")
    last_sync REAL               -- timestamp последней синхронизации
);
```

### Таблица `activity_logs` (расширенная)

```sql
CREATE TABLE activity_logs (
    id            INTEGER PRIMARY KEY,
    device_id     TEXT NOT NULL REFERENCES devices(id),
    app_id        INTEGER NOT NULL REFERENCES apps(id),
    window_title  TEXT,
    start_time    REAL NOT NULL,
    end_time      REAL NOT NULL,
    is_idle       INTEGER NOT NULL DEFAULT 0,
    tag_id        INTEGER REFERENCES tags(id),
    client_log_id INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_device_client_log ON activity_logs(device_id, client_log_id);
```

### Таблицы `apps` и `tags`

Те же что и на клиенте. Матчатся по `bundle_id` (apps) и `name` (tags).

### Изменения в локальной БД клиента

- `activity_logs` — новая колонка `synced INTEGER DEFAULT 0`
- Локальная таблица настроек — `device_id TEXT` (UUID, генерируется один раз)
- Новая таблица `remote_logs` для данных с других устройств:

```sql
CREATE TABLE remote_logs (
    id            INTEGER PRIMARY KEY,
    device_id     TEXT NOT NULL,
    device_name   TEXT NOT NULL,
    app_name      TEXT NOT NULL,
    bundle_id     TEXT NOT NULL,
    window_title  TEXT,
    start_time    REAL NOT NULL,
    end_time      REAL NOT NULL,
    is_idle       INTEGER NOT NULL DEFAULT 0,
    tag_name      TEXT
);
```

## Sync API (Vapor)

Базовый URL: `http://macmini.local:8080/api/v1`

### POST /devices

Регистрация устройства.

```json
// Request
{ "device_id": "uuid", "name": "MacBook Pro" }
// Response: 200 OK / 201 Created
```

### POST /sync/push

Клиент отправляет новые данные на сервер.

```json
// Request
{
  "device_id": "uuid",
  "apps": [
    { "bundle_id": "com.apple.Safari", "app_name": "Safari" }
  ],
  "tags": [
    { "name": "Work", "color_light": "#FF0000", "color_dark": "#CC0000" }
  ],
  "logs": [
    {
      "client_log_id": 42,
      "bundle_id": "com.apple.Safari",
      "window_title": "GitHub",
      "start_time": 1708500000.0,
      "end_time": 1708501800.0,
      "is_idle": false,
      "tag_name": "Work"
    }
  ]
}
// Response
{ "synced_count": 15 }
```

### GET /sync/pull?device_id=uuid&since=timestamp

Клиент получает записи других устройств.

```json
// Response
{
  "logs": [
    {
      "device_id": "other-uuid",
      "device_name": "Mac Mini",
      "bundle_id": "com.jetbrains.intellij",
      "app_name": "IntelliJ IDEA",
      "window_title": "project.swift",
      "start_time": 1708500000.0,
      "end_time": 1708501800.0,
      "is_idle": false,
      "tag_name": "Work"
    }
  ],
  "server_time": 1708501900.0
}
```

**Ключевые решения:**
- Push/pull вместо WebSocket — проще, надёжнее, достаточно для этого кейса
- Ссылки по `bundle_id` / `tag_name` вместо числовых ID — разные маки имеют разные локальные ID
- `since` параметр — клиент тянет только новые записи с последнего sync
- Иконки не синхронизируются — каждый мак генерирует свои

## Sync-логика клиента

### SyncManager (новый сервис)

Таймер каждые 60 секунд:

1. `HEAD /health` — проверка доступности сервера
   - Недоступен → пропустить, попробовать через 60 сек
2. **PUSH:** выбрать записи с `synced = 0`, отправить `POST /sync/push` (батчами по ~100)
   - Успех → пометить `synced = 1`
3. **PULL:** `GET /sync/pull?since=<last_pull_timestamp>`
   - Записи других устройств → `remote_logs`
   - Обновить `last_pull_timestamp`

Работает в background, не блокирует основной поток.

## UI-изменения

- DetailViewController: фильтр "Все устройства / Этот Mac / Mac Mini"
- Таблица сессий: лейбл устройства
- Timeline-бары: объединяют данные со всех устройств

## Структура серверного проекта

```
EmpTrackingServer/            ← новый Swift Package (Vapor)
  ├── Package.swift
  ├── Sources/
  │   ├── App/
  │   │   ├── configure.swift
  │   │   ├── routes.swift
  │   │   ├── Controllers/
  │   │   │   └── SyncController.swift
  │   │   └── Models/
  │   │       ├── Device.swift
  │   │       ├── ActivityLog.swift
  │   │       └── ...
  │   └── Run/
  │       └── main.swift
  └── Tests/
```

## Деплой сервера

Сервер как launchd-сервис на Mac Mini:

- `~/Library/LaunchAgents/com.emptracking.server.plist`
- Запускается при логине, перезапускается при падении
- Логи: `~/Library/Logs/EmpTracking/server.log`
- Порт `8080`, слушает на всех интерфейсах
- Сборка: `swift build -c release`
