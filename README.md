# СДВГ-трекер

Local-first трекер задач для людей с СДВГ: разовые задачи с автопереносом и счётчиком переносов,
рутины, дедлайны, стрик и heatmap активности. Клиенты — Web (Vue) и iOS, сервер синхронизации — FastAPI.

- Архитектура: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- План: [docs/ROADMAP.md](docs/ROADMAP.md)
- Общие контракты (схемы, HLC, фикстуры): [shared/README.md](shared/README.md)

## Быстрый старт

Нужны Docker, [uv](https://docs.astral.sh/uv/) и Node 22.

```bash
make up        # создаст .env со случайным токеном и поднимет всё в docker
```

Открыть http://localhost:8420 → «Настройки» → вставить токен (`API_TOKEN` из `.env`) → «Подключить». Наружу публикуется один порт (`PORT` в `.env`): nginx отдаёт веб
и проксирует `/api` на backend. iOS-клиент ходит на тот же адрес.

## iOS

```bash
make ios-open      # открыть проект в Xcode
make test-ios      # тесты ядра SDVGCore на общих фикстурах
```

- Проект: `ios/SDVGTracker.xcodeproj`, логика — Swift-пакет `ios/SDVGCore` (GRDB, те же правила и протокол).
- На телефоне: в Xcode выбрать свою команду (Signing & Capabilities → Team), при необходимости сменить
  bundle id `com.tirinox.sdvgtracker` и App Group `group.com.tirinox.sdvgtracker` на свои.
- Адрес сервера в приложении — IP компьютера в той же сети: `http://192.168.x.x:8420`
  (в симуляторе работает `http://localhost:8420`). Токен хранится в Keychain.
- Если в глобальном git-конфиге стоит `safe.bareRepository=explicit`, SwiftPM не может скачать GRDB.
  `make ios-open` и цели Makefile переопределяют это только для своих команд.

## Разработка

```bash
make install       # зависимости backend и web
make backend-dev   # backend с перезагрузкой на :8421
make web-dev       # Vite на :5173, /api проксируется на :8421
make test          # тесты backend (включая проверку контрактов shared/) и web
make test-live     # web-клиент синхронизации против настоящего backend на временной БД
make seed          # демо-данные на запущенный сервер: ~24 рутины, ~40 задач, история за 4 месяца
make seed-clear    # убрать демо-данные (через синхронизацию — со всех устройств)
make lint          # ruff + vue-tsc
make help          # все команды
```

```
backend/   FastAPI, uv, pytest
web/       Vue 3 + Vite + TypeScript, Dexie (IndexedDB), Vitest
           src/core — HLC, ID, слияние; src/domain — правила; src/db — локальная БД и действия;
           src/sync — клиент /api/sync и триггеры; src/app — модели экранов; src/views — экраны
shared/    JSON Schema, тест-векторы, фикстуры синхронизации и доменной логики
docs/      архитектура и план
```
