.DEFAULT_GOAL := help
.PHONY: help build run run-direct test check clean
# Both SwiftPM backends share .build; keep their commands sequential.
.NOTPARALLEL:

APP := $(CURDIR)/dist/Обещал.app

help:
	@printf '%s\n' 'make build       Собрать .app' 'make run         Собрать и открыть приложение' 'make run-direct  Запустить исполняемый файл напрямую' 'make test        Запустить тесты' 'make check       Проверить скрипты, тесты и release-сборку' 'make clean       Удалить .build и dist; личные данные сохраняются'

build:
	./scripts/build-app.sh

run: build
	open "$(APP)"

run-direct: build
	"$(APP)/Contents/MacOS/Obeshchal"

test:
	./scripts/test.sh

check:
	bash -n scripts/build-app.sh scripts/test.sh
	$(MAKE) test
	$(MAKE) build

clean:
	rm -rf -- .build dist
