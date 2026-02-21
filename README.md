# EmpTracking

Трекер активности для macOS. Отслеживает какие приложения используются, сколько времени, поддерживает теги и синхронизацию между маками.

## Структура проекта

```
EmpTracking/                  # macOS клиент (Swift, AppKit)
├── AppDelegate.swift         # Точка входа, menubar, popover
├── Models/                   # ActivityLog, AppSummary, Tag, RemoteLog
├── Services/
│   ├── ActivityTracker.swift # Отслеживание активного приложения
│   ├── DatabaseManager.swift # SQLite — локальная БД
│   ├── IdleStateMonitor.swift# Детекция простоя
│   └── SyncManager.swift     # Push/pull синхронизация с сервером
└── Views/
    ├── TimelineViewController.swift  # Popover — список приложений/тегов за день
    ├── DetailViewController.swift    # Окно "Подробнее" — графики, история
    ├── TimelineCellView.swift        # Ячейка приложения
    └── TagCellView.swift             # Ячейка тега

EmpTrackingServer/            # Сервер синхронизации (Swift, Vapor)
├── Sources/App/
│   ├── Controllers/          # DeviceController, SyncController
│   ├── Models/               # Device, App, Tag, ActivityLog (Fluent)
│   ├── DTOs/                 # DeviceDTO, SyncDTO
│   ├── Migrations/           # CreateTables
│   ├── configure.swift       # SQLite + миграции
│   └── routes.swift          # /health, /api/v1/*
└── deploy/
    ├── install.sh            # Скрипт установки как LaunchAgent
    └── com.emptracking.server.plist
```

## Установка сервера (на маке который будет хранить данные)

Требуется Xcode или Command Line Tools (для Swift).

```bash
git clone git@github.com:s-emp/EmpTracking.git
cd EmpTracking/EmpTrackingServer/deploy
chmod +x install.sh
./install.sh
```

Скрипт:
- Собирает сервер в release
- Копирует бинарник в `~/EmpTrackingServer/`
- Устанавливает LaunchAgent — сервер запускается при логине и перезапускается при падении
- БД: `~/EmpTrackingServer/emptracking-server.sqlite`
- Логи: `~/Library/Logs/EmpTracking/server.log`

Проверка:
```bash
curl http://localhost:8080/health
```

Узнать имя мака для клиентов:
```bash
scutil --get LocalHostName
```

## Установка клиента

### Сборка из исходников (на маке с Xcode)

```bash
cd EmpTracking
xcodebuild build \
  -scheme EmpTracking \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO
```

Собранное приложение будет в `DerivedData`. Скопировать в `/Applications`:
```bash
BUILD_DIR=$(xcodebuild -scheme EmpTracking -configuration Release \
  -showBuildSettings 2>/dev/null | grep ' TARGET_BUILD_DIR' | xargs | cut -d= -f2 | xargs)
cp -R "$BUILD_DIR/EmpTracking.app" /Applications/
```

### Установка готового .app (на маке без Xcode)

1. Скопировать `EmpTracking.app` в `/Applications`
2. Снять карантинный флаг (приложение без подписи):
   ```bash
   xattr -cr /Applications/EmpTracking.app
   ```
3. Запустить

### Настройка адреса сервера

По умолчанию клиент подключается к `http://macmini.local:8080`. Если сервер на другом маке:

```bash
defaults write com.emp.s.EmpTracking syncServerUrl "http://<имя-сервера>.local:8080"
```

После изменения перезапустить приложение.

## Как работает синхронизация

- Каждый мак ведет локальную БД: `~/Library/Application Support/EmpTracking/tracking.db`
- Каждые 60 секунд клиент пушит несинхронизированные логи на сервер и пуллит логи с других устройств
- Сервер — единственный источник правды для данных со всех маков
- В popover отображается статус синхронизации (синхронизировано / ожидание / ошибка)

## API сервера

| Метод | Путь | Описание |
|-------|------|----------|
| HEAD | `/health` | Проверка доступности |
| POST | `/api/v1/devices` | Регистрация устройства |
| POST | `/api/v1/sync/push` | Загрузка логов на сервер |
| GET | `/api/v1/sync/pull?device_id=...&since=...` | Получение логов с других устройств |

## Управление сервером

```bash
# Статус
launchctl print gui/$(id -u)/com.emptracking.server

# Остановить
launchctl bootout gui/$(id -u)/com.emptracking.server

# Запустить
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.emptracking.server.plist

# Логи
tail -f ~/Library/Logs/EmpTracking/server.log
```
