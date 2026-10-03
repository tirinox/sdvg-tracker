.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help env token connect install up down build logs ps test test-backend test-web \
        test-live test-ios test-ios-live ios-build ios-open ios-install ios-daily-on ios-daily-off seed seed-clear import lint fmt backend-dev web-dev \
        emoji-model emoji-catalog \
        backup reset-db restore deploy deploy-logs connect-prod videos videos-deploy

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
	@$(MAKE) --no-print-directory emoji-model

emoji-model: ## Download the emoji suggestion model (~120 MB) into backend/models
	cd backend && uv run python scripts/fetch_emoji_model.py models/multilingual-e5-small

emoji-catalog: ## Regenerate the emoji catalog (backend/app/emoji/catalog.tsv) from Unicode CLDR
	cd backend && uv run python scripts/emoji_catalog.py

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

# A free Personal Team can't get the App Group, so the app is signed without entitlements:
# it keeps its database in Application Support and the widgets see no data.
IOS_TEAM ?= 7L32PPK723
IOS_DEVICE ?=
IOS_LAUNCH ?= 1

ios-install: ## Build, install and launch on a connected iPhone (IOS_DEVICE=<udid>, IOS_TEAM=<team id>, IOS_LAUNCH=0)
	@udid="$(IOS_DEVICE)"; \
	if [ -z "$$udid" ]; then \
		tmp=$$(mktemp); xcrun devicectl list devices --json-output $$tmp >/dev/null 2>&1; \
		udid=$$(python3 -c 'import json, sys; ds = json.load(open(sys.argv[1]))["result"]["devices"]; \
			print(next((d["hardwareProperties"]["udid"] for d in ds if d["hardwareProperties"].get("deviceType") == "iPhone" \
			and d["connectionProperties"].get("tunnelState") != "unavailable"), ""))' $$tmp); \
		rm -f $$tmp; \
	fi; \
	test -n "$$udid" || { echo "No iPhone available: unlock it and connect by cable or the same Wi-Fi"; exit 1; }; \
	echo "Device: $$udid"; \
	mkdir -p ios/build; \
	( cd ios && $(SWIFT_ENV) xcodebuild -project SDVGTracker.xcodeproj -scheme SDVGTracker -configuration Debug \
		-destination "id=$$udid" -derivedDataPath build/device DEVELOPMENT_TEAM=$(IOS_TEAM) CODE_SIGN_ENTITLEMENTS= \
		-allowProvisioningUpdates build ) > ios/build/device.log 2>&1 \
		|| { grep -E "error:" ios/build/device.log; echo "Build failed, full log: ios/build/device.log"; exit 1; }; \
	echo "Built"; \
	xcrun devicectl device install app --device $$udid ios/build/device/Build/Products/Debug-iphoneos/SDVGTracker.app \
		>/dev/null || { echo "Install failed"; exit 1; }; \
	echo "Installed"; \
	[ "$(IOS_LAUNCH)" = 0 ] && exit 0; \
	xcrun devicectl device process launch --device $$udid com.tirinox.sdvgtracker >/dev/null 2>&1 \
		&& echo "Launched" || echo "Installed, but not launched: unlock the phone and open the app"

ios-daily-on: ## Install on the iPhone once a day by itself (launchd, hourly tries until the phone is reachable)
	@scripts/ios-daily.sh on

ios-daily-off: ## Stop the daily install
	@scripts/ios-daily.sh off

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

IMPORT_FILE ?= private/tasks.json

import: ## Load routines and tasks from IMPORT_FILE (default private/tasks.json) into an empty server
	cd web && SDVG_TOKEN=$(SEED_TOKEN) npx tsx scripts/import.ts --url $(SEED_URL) --file $(CURDIR)/$(IMPORT_FILE)

backend-dev: env ## Run backend locally with reload on :8421
	cd backend && uv run uvicorn --factory app.main:create_app --reload --port 8421

web-dev: ## Run Vite dev server on :5173 (proxies /api to :8421)
	cd web && npm run dev

# Production: /srv/sdvg on the server, behind the host's shared ingress (see README).
DEPLOY_HOST := exleader
DEPLOY_DIR  := /srv/sdvg
DEPLOY_URL  := https://sdvg.thornode.org
BACKUP_DIR  := backups
STAMP       := $(shell date +%Y%m%d-%H%M%S)

deploy: ## Roll the server forward to origin/main (push first)
	ssh $(DEPLOY_HOST) 'cd $(DEPLOY_DIR) && git pull --ff-only && docker compose up -d --build --wait'
	@curl -fsS -m 10 $(DEPLOY_URL)/api/health && echo

deploy-logs: ## Tail the server's logs
	ssh -t $(DEPLOY_HOST) 'cd $(DEPLOY_DIR) && docker compose logs -f --tail=100'

connect-prod: ## Server address and token for the clients (token goes to clipboard)
	@token=$$(ssh $(DEPLOY_HOST) "grep -E '^API_TOKEN=' $(DEPLOY_DIR)/.env | cut -d= -f2"); \
	echo "Address: $(DEPLOY_URL)"; \
	if command -v pbcopy >/dev/null; then printf %s "$$token" | pbcopy && echo "Token copied to clipboard"; \
	else echo "Token:   $$token"; fi

videos: ## Name new videos in video/ goodmorning-NNN.mp4 and write video/index.json
	python3 scripts/goodmorning.py video

# video/ is not in git: it goes to the server beside the checkout, nginx serves it at /video/.
# Deletions come last, so the old index never points at a missing file.
videos-deploy: videos ## Upload video/ to the server: the iOS app's morning videos
	rsync -rtz --delete-after --chmod=D755,F644 --exclude .DS_Store video/ $(DEPLOY_HOST):$(DEPLOY_DIR)/video/
	@curl -fsS -m 10 $(DEPLOY_URL)/video/index.json \
		| python3 -c 'import json, sys; print(len(json.load(sys.stdin)["videos"]), "videos online")'

backup: ## Snapshot the database into backups/ (consistent while running; the server's cron runs this)
	@mkdir -p $(BACKUP_DIR)
	@# Streamed out rather than written to a mount, which works whatever user the container
	@# runs as. SQLite's backup API gives a consistent copy even mid-sync.
	$(COMPOSE) exec -T backend python -c "import os, sqlite3, sys; \
		src = sqlite3.connect(os.environ['DATABASE_PATH']); dst = sqlite3.connect(':memory:'); \
		src.backup(dst); sys.stdout.buffer.write(dst.serialize())" \
		> $(BACKUP_DIR)/sdvg-$(STAMP).db || { rm -f $(BACKUP_DIR)/sdvg-$(STAMP).db; exit 1; }
	gzip $(BACKUP_DIR)/sdvg-$(STAMP).db
	@echo "Wrote $(BACKUP_DIR)/sdvg-$(STAMP).db.gz"

reset-db: ## Empty the database (after a backup); synced devices ask before merging into it
	@read -p "Empty the database of $(CURDIR)? Type yes: " a && [ "$$a" = yes ]
	@$(MAKE) --no-print-directory backup
	$(COMPOSE) exec -T backend python -m app.admin reset

restore: ## Replace the database with FILE=backups/….db.gz (after a backup); devices push back what it lacks
	@test -f "$(FILE)" || { echo "usage: make restore FILE=$(BACKUP_DIR)/sdvg-….db.gz"; exit 1; }
	@read -p "Replace the database of $(CURDIR) with $(FILE)? Type yes: " a && [ "$$a" = yes ]
	@$(MAKE) --no-print-directory backup
	@# The backup keeps server_id; restore gives it a new epoch, so devices re-send their rows.
	case "$(FILE)" in *.gz) gunzip -c "$(FILE)" ;; *) cat "$(FILE)" ;; esac \
		| $(COMPOSE) exec -T backend python -m app.admin restore
	$(COMPOSE) restart backend
