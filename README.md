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

Открыть http://localhost:8420. Наружу публикуется один порт (`PORT` в `.env`): nginx отдаёт веб
и проксирует `/api` на backend. iOS-клиент ходит на тот же адрес.

## Разработка

```bash
make install       # зависимости backend и web
make backend-dev   # backend с перезагрузкой на :8421
make web-dev       # Vite на :5173, /api проксируется на :8421
make test          # тесты backend (включая проверку контрактов shared/) и web
make lint          # ruff + vue-tsc
make help          # все команды
```

```
backend/   FastAPI, uv, pytest
web/       Vue 3 + Vite + TypeScript, Vitest
shared/    JSON Schema, тест-векторы, фикстуры синхронизации и доменной логики
docs/      архитектура и план
```
