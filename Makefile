.PHONY: help deploy sync install build-docker dev devmac dump dumpimport seed migration migrate rollback test tt lint security-check format refactor doc twitch routes provision

isDocker := $(shell docker info > /dev/null 2>&1 && echo 1)
isProd := $(shell grep "APP_ENV=prod" .env.local > /dev/null && echo 1)
domain := "grafikart.fr"
server := "grafikart"
user := $(shell id -u)
group := $(shell id -g)

sy := php bin/console
bun :=
php :=
ifeq ($(isDocker), 1)
	ifneq ($(isProd), 1)
		dc := USER_ID=$(user) GROUP_ID=$(group) docker compose
		dcimport := USER_ID=$(user) GROUP_ID=$(group) docker compose -f docker-compose.import.yml
		de := docker compose exec
		dr := $(dc) run --rm
		drtest := $(dc) -f docker-compose.test.yml run --rm
		sy := $(de) php bin/console
		bun := $(dr) bun
		php := $(dr) --no-deps php
	endif
endif

.DEFAULT_GOAL := help
help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

deploy: ## Déploie une nouvelle version du site
	ssh -A $(server) 'cd $(domain) && git pull origin master && make install'

devdeploy: ## Déploie une nouvelle version du site
	ssh -A $(server) 'cd dev.$(domain) && git pull origin develop && make install'

sync: ## Récupère les données depuis le serveur
	rsync -avz --ignore-existing --progress --exclude=avatars grafikart:/home/grafikart/grafikart.fr/public/uploads/ ./public/uploads/

install: vendor/autoload.php public/assets/.vite/manifest.json ## Installe les différentes dépendances
	APP_ENV=prod APP_DEBUG=0 $(php) composer install --no-dev --optimize-autoloader
	make migrate
	APP_ENV=prod APP_DEBUG=0 $(sy) cache:clear
	APP_ENV=prod APP_DEBUG=0 $(sy) cache:pool:clear cache.global_clearer
	$(sy) messenger:stop-workers
	sudo service php8.2-fpm reload

build-docker:
	$(dc) pull --ignore-pull-failures
	$(dc) build php
	$(dc) build messenger

dev: node_modules/time ## Lance le serveur de développement
	$(dc) up

devmac: ## Sur MacOS on ne préfèrera exécuter PHP en local pour les performances
	docker compose -f docker-compose.macos.yml up

dump: var/dump ## Génère un dump SQL
	$(de) db sh -c 'PGPASSWORD="grafikart" pg_dump grafikart -U grafikart > /var/www/var/dump/dump.sql'

dumpimport: ## Import un dump SQL
	$(de) db sh -c 'pg_restore -c -d grafikart -U grafikart /var/www/var/dump'

seed: vendor/autoload.php ## Génère des données dans la base de données (docker compose up doit être lancé)
	$(sy) doctrine:migrations:migrate -q
	$(sy) app:seed -q

migration: vendor/autoload.php ## Génère les migrations
	$(sy) make:migration

migrate: vendor/autoload.php ## Migre la base de données (docker compose up doit être lancé)
	$(sy) doctrine:migrations:migrate -q

rollback:
	$(sy) doctrine:migration:migrate prev

test: vendor/autoload.php node_modules/time ## Execute les tests
	$(drtest) phptest bin/console doctrine:schema:validate --skip-sync
	$(drtest) phptest vendor/bin/paratest -p 4 --runner=WrapperRunner
	# (drtest) phptest bin/phpunit
	$(bun) bun run test

tt: vendor/autoload.php ## Lance le watcher phpunit
	$(drtest) phptest bin/console doctrine:schema:validate --skip-sync
	$(drtest) phptest bin/phpunit
	# $(drtest) phptest bin/console cache:clear --env=test
	# $(drtest) phptest vendor/bin/phpunit-watcher watch --filter="nothing"

lint: vendor/autoload.php ## Analyse le code
	docker run -v $(PWD):/app -w /app -t --rm grafikart/php:php8.2-2 php -d memory_limit=-1 bin/console lint:container
	docker run -v $(PWD):/app -w /app -t --rm grafikart/php:php8.2-2 php -d memory_limit=-1 ./vendor/bin/phpstan analyse

security-check: vendor/autoload.php ## Check pour les vulnérabilités des dependencies
	$(de) php local-php-security-checker --path=/var/www

format: ## Formate le code
	bunx prettier-standard --lint --changed "assets/**/*.{js,css,jsx}"
	docker run -v $(PWD):/app -w /app -t --rm grafikart/php:php8.2-2 php -d memory_limit=-1 ./vendor/bin/php-cs-fixer fix

refactor: ## Reformate le code avec rector
	docker run -v $(PWD):/app -w /app -t --rm grafikart/php:php8.2-2 php -d memory_limit=-1 ./vendor/bin/rector process src

doc: ## Génère le sommaire de la documentation
	npx doctoc ./README.md

twitch:
	twitch event trigger stream.online -F http://localhost:8000/twitch/webhook -s testsecret

routes:
	$(de) php bin/console cache:clear

# -----------------------------------
# Déploiement
# -----------------------------------
provision: ## Configure la machine distante
	ansible-playbook --vault-password-file .vault_pass -i tools/ansible/hosts.yml tools/ansible/install.yml

# -----------------------------------
# Dépendances
# -----------------------------------
vendor/autoload.php: composer.lock
	$(php) composer install
	touch vendor/autoload.php

node_modules/time: bun.lockb
	$(bun) bun install
	touch node_modules/time

bun.lockb:
	$(bun) bun install

public/assets: node_modules/time
	$(bun) run build

var/dump:
	mkdir var/dump

public/assets/.vite/manifest.json: package.json
	$(bun) bun install
	$(bun) bun run build
