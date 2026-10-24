# Команды проекта. Список: make help
export R_LIBS_USER ?= $(HOME)/R/lib
ADDR ?= :8080
PORT := $(patsubst :%,%,$(ADDR))
PIDFILE := bin/server.pid
LOGFILE := bin/server.log

help: ## показать список команд
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-12s %s\n", $$1, $$2}'

install: ## установить зависимости (R: jsonlite, npm-пакеты)
	Rscript analysis/install.R
	cd frontend && npm install

build-web: ## собрать фронтенд
	cd frontend && npm run build

build-api: ## собрать Go-сервер в bin/server
	cd backend && go build -o ../bin/server ./cmd/server

build: build-web build-api ## собрать всё

test: ## запустить тесты Go и R
	cd backend && go vet ./... && go test ./...
	Rscript analysis/tests/test_stats.R

run: build ## собрать и запустить сервер на переднем плане (ADDR=:8080)
	./bin/server -root . -addr $(ADDR)

start: build ## собрать и запустить сервер в фоне (лог: bin/server.log)
	@$(MAKE) --no-print-directory stop
	@nohup ./bin/server -root . -addr $(ADDR) > $(LOGFILE) 2>&1 & echo $$! > $(PIDFILE)
	@echo "Сервер запущен: http://localhost:$(PORT)  (PID $$(cat $(PIDFILE)))"

stop: ## остановить фоновый сервер
	@if [ -f $(PIDFILE) ]; then kill $$(cat $(PIDFILE)) 2>/dev/null && echo "Сервер остановлен"; rm -f $(PIDFILE); fi

logs: ## показать лог фонового сервера
	@tail -f $(LOGFILE)

dev: ## режим разработки: сервер + Vite с горячей перезагрузкой (http://localhost:5173)
	cd backend && go build -o ../bin/server ./cmd/server
	./bin/server -root . -addr $(ADDR) & trap "kill $$!" EXIT; cd frontend && npm run dev

fetch: ## загрузить данные по всем точкам (сервер должен работать)
	curl -s -X POST http://localhost:$(PORT)/api/fetch; echo

status: ## показать ход загрузки данных
	@curl -s http://localhost:$(PORT)/api/status; echo

clean: ## удалить сборку (данные data/raw сохраняются)
	rm -rf bin frontend/dist

clean-data: ## удалить загруженные данные
	rm -f data/raw/*.csv

.PHONY: help install build-web build-api build test run start stop logs dev fetch status clean clean-data
