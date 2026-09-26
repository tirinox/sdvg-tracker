.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help env token connect install up down build logs ps test test-backend test-web \
        test-live test-ios test-ios-live ios-build ios-open seed seed-clear lint fmt backend-dev web-dev

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

env: ## Create .env with a random token (if missing)
	@test -f .env || { sed "s/^API_TOKEN=.*/API_TOKEN=$$(openssl rand -hex 24)/" .env.example > .env && echo "Created .env"; }

token: ## Print a new random token
	@openssl rand -hex 24

connect: ## Server address on the local network and token for the iOS app (token goes to clipboard)
	@test -f .env || { echo "No .env: run make up first"; exit 1; }
	@iface=$$(route -n get default 2>/dev/null | awk '/interface:/ {print $$2}'); \
	ip=$$(ipconfig getifaddr $${iface:-en0} 2>/dev/null || hostname -I 2>/dev/null | awk '{print $$1}'); \
	port=$$(grep -E '^PORT=' .env | cut -d= -f2); port=$${port:-8420}; \
	token=$$(grep -E '^API_TOKEN=' .env | cut -d= -f2); \
	url="http://$$ip:$$port"; \
	echo "Address: $$url"; \
	echo "Token:   $$token"; \
	if curl -sf -m 3 "$$url/api/health" >/dev/null; then echo "Server:  reachable"; \
	else echo "Server:  not responding at $$url (make up?)"; fi; \
	if command -v pbcopy >/dev/null; then printf %s "$$token" | pbcopy && echo "Token copied to clipboard"; fi

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

test: test-backend test-web test-ios ## Run all tests

test-backend:
	cd backend && uv run pytest

test-web:
	cd web && npx vitest run

# SwiftPM keeps bare repositories in its cache; a global safe.bareRepository=explicit breaks it.
SWIFT_ENV := GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.bareRepository GIT_CONFIG_VALUE_0=all

test-ios: ## iOS core (SDVGCore): shared fixtures, store, sync
	cd ios/SDVGCore && $(SWIFT_ENV) swift test

LIVE_PORT := 8422
LIVE_TOKEN := live-test-token-0123456789

test-live: ## Web sync client against a real backend on a throwaway database
	@cd backend && uv sync -q
	@tmp=$$(mktemp -d); \
	( cd backend && API_TOKEN=$(LIVE_TOKEN) DATABASE_PATH=$$tmp/live.db exec .venv/bin/uvicorn \
		--factory app.main:create_app --port $(LIVE_PORT) --log-level warning ) & \
	pid=$$!; trap 'kill $$pid 2>/dev/null; rm -rf $$tmp' EXIT; \
	for i in $$(seq 50); do curl -sf localhost:$(LIVE_PORT)/api/health >/dev/null && break; sleep 0.2; done; \
	cd web && SDVG_LIVE_URL=http://localhost:$(LIVE_PORT) SDVG_LIVE_TOKEN=$(LIVE_TOKEN) \
		npx vitest run src/sync/live.test.ts

lint: ## Lint and typecheck
	cd backend && uv run ruff check . && uv run ruff format --check .
	cd web && npm run typecheck

fmt: ## Format code
	cd backend && uv run ruff check --fix . && uv run ruff format .

ios-build: ## Build the iOS app for the simulator
	cd ios && $(SWIFT_ENV) xcodebuild -project SDVGTracker.xcodeproj -scheme SDVGTracker \
		-destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData build | tail -3

ios-open: ## Open the iOS project in Xcode (git override so Xcode can fetch GRDB)
	$(SWIFT_ENV) open ios/SDVGTracker.xcodeproj

test-ios-live: ## iOS sync client against a real backend on a throwaway database
	@cd backend && uv sync -q
	@tmp=$$(mktemp -d); \
	( cd backend && API_TOKEN=$(LIVE_TOKEN) DATABASE_PATH=$$tmp/live.db exec .venv/bin/uvicorn \
		--factory app.main:create_app --port $(LIVE_PORT) --log-level warning ) & \
	pid=$$!; trap 'kill $$pid 2>/dev/null; rm -rf $$tmp' EXIT; \
	for i in $$(seq 50); do curl -sf localhost:$(LIVE_PORT)/api/health >/dev/null && break; sleep 0.2; done; \
	cd ios/SDVGCore && SDVG_LIVE_URL=http://localhost:$(LIVE_PORT) SDVG_LIVE_TOKEN=$(LIVE_TOKEN) \
		$(SWIFT_ENV) swift test --filter LiveSyncTests

SEED_URL ?= http://localhost:$$(grep -E '^PORT=' $(CURDIR)/.env | cut -d= -f2)
SEED_TOKEN = $$(grep -E '^API_TOKEN=' $(CURDIR)/.env | cut -d= -f2)

seed: ## Fill the running server (make up) with demo data: routines, tasks, 4 months of history
	cd web && SDVG_TOKEN=$(SEED_TOKEN) npx tsx scripts/seed.ts --url $(SEED_URL)

seed-clear: ## Remove the demo data from the server and, after sync, from every device
	cd web && SDVG_TOKEN=$(SEED_TOKEN) npx tsx scripts/seed.ts --url $(SEED_URL) --clear

backend-dev: env ## Run backend locally with reload on :8421
	cd backend && uv run uvicorn --factory app.main:create_app --reload --port 8421

web-dev: ## Run Vite dev server on :5173 (proxies /api to :8421)
	cd web && npm run dev
