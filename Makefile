# clickhouse-start — convenience commands.
# Run `make help` to see everything.

# Load .env if present so CLICKHOUSE_* vars are available; otherwise use defaults.
-include .env
export

CLICKHOUSE_USER ?= learner
CLICKHOUSE_PASSWORD ?= learn
CLICKHOUSE_DB ?= learn

# Run clickhouse-client inside the container as the learner user.
CLIENT = docker compose exec -T clickhouse clickhouse-client \
	--user $(CLICKHOUSE_USER) --password $(CLICKHOUSE_PASSWORD) --database $(CLICKHOUSE_DB)

.DEFAULT_GOAL := help

.PHONY: help up down restart logs ps wait client load-data lesson clean nuke

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Start ClickHouse (detached) and wait until it's ready
	docker compose up -d
	@$(MAKE) --no-print-directory wait
	@echo "ClickHouse is up. Play UI: http://localhost:8123/play  (user: $(CLICKHOUSE_USER) / pass: $(CLICKHOUSE_PASSWORD))"

down: ## Stop the container (keeps data volume)
	docker compose down

restart: ## Restart the container
	docker compose restart

logs: ## Follow server logs
	docker compose logs -f clickhouse

ps: ## Show container status
	docker compose ps

wait: ## Block until the server answers SELECT 1
	@echo "Waiting for ClickHouse..."
	@until docker compose exec -T clickhouse clickhouse-client --query "SELECT 1" >/dev/null 2>&1; do \
		printf '.'; sleep 1; \
	done; echo " ready."

client: ## Open an interactive clickhouse-client session
	docker compose exec clickhouse clickhouse-client \
		--user $(CLICKHOUSE_USER) --password $(CLICKHOUSE_PASSWORD) --database $(CLICKHOUSE_DB)

# Run a query string:        make q Q="SELECT version()"
q: ## Run an inline query: make q Q="SELECT version()"
	@echo "$(Q)" | $(CLIENT) --multiquery

# Run a .sql file:           make sql F=lessons/01-primary-keys/lesson.sql
sql: ## Run a .sql file: make sql F=path/to/file.sql
	@$(CLIENT) --multiquery < $(F)

load-data: ## Load the NYC taxi sample dataset (pulls from S3, a few million rows)
	@$(CLIENT) --multiquery < data-loaders/nyc_taxi.sql
	@echo "Loaded. Try: make q Q=\"SELECT count() FROM trips\""

# Run a whole lesson's SQL:  make lesson N=01
lesson: ## Run a lesson's lesson.sql: make lesson N=01
	@f=$$(ls lessons/$(N)-*/lesson.sql); echo "Running $$f"; $(CLIENT) --multiquery < $$f

clean: ## Drop the learn database (fresh start, keeps the container)
	@echo "DROP DATABASE IF EXISTS $(CLICKHOUSE_DB); CREATE DATABASE $(CLICKHOUSE_DB);" | $(CLIENT) --multiquery
	@echo "Database $(CLICKHOUSE_DB) reset."

nuke: ## Stop and delete EVERYTHING including the data volume
	docker compose down -v
