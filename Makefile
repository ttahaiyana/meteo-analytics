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
	@if ss -ltn | grep -q ':$(PORT) '; then echo "Порт $(PORT) занят другим процессом: освободите его или задайте ADDR=:9000"; exit 1; fi
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

fetch-missing: ## докачать только точки без данных (сервер должен работать)
	@ids=$$(curl -s http://localhost:$(PORT)/api/locations | python3 -c "import sys,json; print(json.dumps([l['id'] for l in json.load(sys.stdin) if not l['data']]))") && \
	if [ "$$ids" = "[]" ]; then echo "Все точки уже загружены"; else \
	echo "Докачиваем: $$ids"; \
	curl -s -X POST http://localhost:$(PORT)/api/fetch -H 'Content-Type: application/json' -d "{\"ids\":$$ids}"; echo; fi

status: ## показать ход загрузки данных
	@curl -s http://localhost:$(PORT)/api/status; echo

check: ## проверить, что загружены все точки (для презентации)
	@curl -s http://localhost:$(PORT)/api/locations | python3 -c "import sys,json; l=json.load(sys.stdin); miss=[x['name'] for x in l if not x['data']]; print('Загружено %d из %d' % (len(l)-len(miss), len(l))); print('Не хватает: ' + ', '.join(miss)) if miss else print('Все точки на месте'); sys.exit(1 if miss else 0)"

warmup: ## прогреть кэш: посчитать все вкладки для всех точек
	@curl -s http://localhost:$(PORT)/api/locations | python3 -c "import sys,json; print(' '.join(x['id'] for x in json.load(sys.stdin) if x['data']))" > bin/.ids
	@for m in compare insights quality; do curl -s -o /dev/null "http://localhost:$(PORT)/api/analysis/$$m"; done
	@for v in tmean tmax tmin precip wind; do curl -s -o /dev/null "http://localhost:$(PORT)/api/analysis/trends?var=$$v"; done
	@for id in $$(cat bin/.ids); do \
		for m in seasonality extremes correlations; do curl -s -o /dev/null "http://localhost:$(PORT)/api/analysis/$$m?loc=$$id"; done; \
		curl -s -o /dev/null "http://localhost:$(PORT)/api/analysis/trends?loc=$$id&var=tmean"; \
		echo "  готово: $$id"; \
	done
	@echo "Кэш прогрет: вкладки откроются мгновенно"

backup-data: ## сохранить копию загруженных данных в backup/raw
	mkdir -p backup/raw && cp data/raw/*.csv backup/raw/
	@echo "Копия: backup/raw ($$(ls backup/raw | wc -l) файлов)"

restore-data: ## вернуть данные из backup/raw (если лимит или интернет подвели)
	mkdir -p data/raw && cp backup/raw/*.csv data/raw/

demo: start ## презентация: запуск, прогрев кэша, открытие браузера
	@for i in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null http://localhost:$(PORT)/api/status && break; sleep 1; done
	@$(MAKE) --no-print-directory check || echo "Внимание: данные неполные, демо покажет только загруженные точки"
	@$(MAKE) --no-print-directory warmup
	@xdg-open http://localhost:$(PORT) >/dev/null 2>&1 || echo "Откройте http://localhost:$(PORT)"

clean: ## удалить сборку (данные data/raw сохраняются)
	rm -rf bin frontend/dist

clean-data: ## удалить загруженные данные
	rm -f data/raw/*.csv

.PHONY: help install build-web build-api build test run start stop logs dev fetch fetch-missing status check warmup backup-data restore-data demo clean clean-data
