DOCKER_TAG = dev

GULP := node_modules/.bin/gulp

# Unless the user has specified otherwise in their environment, it's probably a
# good idea to refuse to install unless we're in an activated virtualenv.
ifndef PIP_REQUIRE_VIRTUALENV
PIP_REQUIRE_VIRTUALENV = 1
endif
export PIP_REQUIRE_VIRTUALENV

.PHONY: default
default: test

build/manifest.json: node_modules/.uptodate
	$(GULP) build

## Clean up runtime artifacts (needed after a version update)
.PHONY: clean
clean:
	find . -type f -name "*.py[co]" -delete
	find . -type d -name "__pycache__" -delete
	rm -f node_modules/.uptodate .pydeps
	rm -rf build

## Run the development H server locally
.PHONY: dev
dev: build/manifest.json .pydeps
	@bin/hypothesis --dev init
	@bin/hypothesis devserver

## Build hypothesis/hypothesis docker image
.PHONY: docker
docker:
	git archive HEAD | docker build -t hypothesis/hypothesis:$(DOCKER_TAG) -

# Run docker image built with `docker` task
.PHONY: run-docker
run-docker:
	$(eval RABBITMQ_CONTAINER ?= rabbitmq)
	$(eval PG_CONTAINER ?= postgres)
	$(eval ES_CONTAINER ?= elasticsearch1)
	$(eval BROKER_URL ?= amqp://guest:guest@$(RABBITMQ_CONTAINER):5672//)
	docker run \
		--link $(RABBITMQ_CONTAINER) \
		--link $(PG_CONTAINER) \
		--link $(ES_CONTAINER) \
		-e "APP_URL=http://localhost:5000" \
		-e "BROKER_URL=$(BROKER_URL)" \
		-e "DATABASE_URL=postgresql://postgres@$(PG_CONTAINER)/postgres" \
		-e "ELASTICSEARCH_HOST=http://$(ES_CONTAINER):9200" \
		-e WEB_NUM_WORKERS=12 \
		-e SECRET_KEY=notasecret \
		-p 5000:5000 \
		hypothesis/hypothesis:$(DOCKER_TAG)

## Run test suite
.PHONY: test
test: node_modules/.uptodate
	@pip install -q tox
	tox
	$(GULP) test

.PHONY: test-py3
test-py3: node_modules/.uptodate
	tox -e py36 -- tests/h/

.PHONY: lint
lint: .pydeps
	flake8 h
	flake8 tests
	flake8 --select FI14 --exclude 'h/cli/*,tests/h/cli/*,h/util/uri.py,h/migrations/versions/*' h tests

################################################################################

# Fake targets to aid with deps installation
.pydeps: requirements.txt requirements-dev.in
	@echo installing python dependencies
	@pip install -r requirements-dev.in tox
	@touch $@

node_modules/.uptodate: package.json
	@echo installing javascript dependencies
	@node_modules/.bin/check-dependencies 2>/dev/null || npm install
	@touch $@

# Self documenting Makefile
.PHONY: help
help:
	@echo "The following targets are available:"
	@echo " clean      Clean up runtime artifacts (needed after a version update)"
	@echo " dev        Run the development H server locally"
	@echo " docker     Build hypothesis/hypothesis docker image"
	@echo " test       Run the test suite (default)"
