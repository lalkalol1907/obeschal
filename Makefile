.DEFAULT_GOAL := help
.PHONY: help build run run-direct test check package clean
# Both SwiftPM backends share .build; keep their commands sequential.
.NOTPARALLEL:

APP := $(CURDIR)/dist/Обещал.app

help:
	@printf '%s\n' 'make build       Собрать .app' 'make run         Собрать и открыть приложение' 'make run-direct  Запустить исполняемый файл напрямую' 'make test        Запустить тесты' 'make check       Проверить скрипты, тесты и release-сборку' 'make package     Создать ZIP/DMG: RELEASE_TAG=v1.2.3 make package' 'make clean       Удалить .build и dist; личные данные сохраняются'

build:
	./scripts/build-app.sh

run: build
	open "$(APP)"

run-direct: build
	"$(APP)/Contents/MacOS/Obeshchal"

test:
	./scripts/test.sh
	./scripts/test-release.sh

check:
	bash -n scripts/*.sh
	$(MAKE) test
	$(MAKE) build

package:
	./scripts/package-release.sh

clean:
	rm -rf -- .build dist
