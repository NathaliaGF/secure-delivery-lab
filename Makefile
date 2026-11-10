.PHONY: test lint scan up down

test:            ## app tests and shell script tests
	python -m pytest -q -c app/pyproject.toml --rootdir app app/tests --cov=app
	./scripts/test_scripts.sh

lint:            ## the same linters as the pipeline
	cd ansible && ansible-lint
	cd infra/terraform && terraform fmt -check -recursive && terraform validate
	hadolint Dockerfile
	shellcheck scripts/*.sh

scan:            ## the same security gates as the pipeline, locally
	dockerscan --dir . --fail-on MEDIUM
	secrets-scanner --dir . --git --severity MEDIUM

up:              ## app + Prometheus + Grafana (set GF_ADMIN_PASSWORD first)
	docker compose -f compose.yml -f compose.observability.yml up -d --build

down:
	docker compose -f compose.yml -f compose.observability.yml down
