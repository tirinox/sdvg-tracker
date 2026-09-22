.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help env token install up down build logs ps test test-backend test-web \
        lint fmt backend-dev web-dev

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

env: ## Create .env with a random token (if missing)
	@test -f .env || { sed "s/^API_TOKEN=.*/API_TOKEN=$$(openssl rand -hex 24)/" .env.example > .env && echo "Created .env"; }

token: ## Print a new random token
	@openssl rand -hex 24

install: ## Install local dev dependencies
	cd backend && uv sync
	cd web && npm install

up: env ## Build and start backend + web in docker
	$(COMPOSE) up -d --build
	@echo "Web: http://localhost:$$(grep -E '^PORT=' .env | cut -d= -f2 || echo 8420)"

down: ## Stop containers
	$(COMPOSE) down

build: ## Build docker images
	$(COMPOSE) build

logs: ## Follow container logs
	$(COMPOSE) logs -f

ps: ## Show container status
	$(COMPOSE) ps

test: test-backend test-web ## Run all tests

test-backend:
	cd backend && uv run pytest

test-web:
	cd web && npx vitest run

lint: ## Lint and typecheck
	cd backend && uv run ruff check . && uv run ruff format --check .
	cd web && npm run typecheck

fmt: ## Format code
	cd backend && uv run ruff check --fix . && uv run ruff format .

backend-dev: env ## Run backend locally with reload on :8421
	cd backend && uv run uvicorn app.main:app --reload --port 8421

web-dev: ## Run Vite dev server on :5173 (proxies /api to :8421)
	cd web && npm run dev
