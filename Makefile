DOCKER_REPO_NAME := my-eidolon-project
VERSION := $(shell grep -m 1 '^version = ' pyproject.toml | awk -F '"' '{print $$2}')
SDK_VERSION := $(shell awk '/^name = "eidolon-ai-sdk"$$/{f=1} f&&/^version = /{gsub(/"|,/,"",$$3); print $$3; exit}' poetry.lock)
REQUIRED_ENVS := OPENAI_API_KEY
MAKEFLAGS += -j2

.PHONY: serve serve-dev check docker-serve .env sync update docker-build pull-webui k8s-operator check-kubectl check-helm check-cluster-running verify-k8s-permissions check-install-operator k8s-serve k8s-env

ARGS ?=

serve-dev: .make/poetry_install .env
	@echo "Starting Server..."
	@poetry run eidolon-server -m local_dev resources --dotenv .env $(ARGS)

serve: .make/poetry_install .env
	@echo "Starting Server..."
	@poetry run eidolon-server resources --dotenv .env $(ARGS)

test: .make/poetry_install .env
	@poetry run pytest tests $(ARGS)

.env: Makefile
	@touch .env
	@for var in $(REQUIRED_ENVS); do \
		if [ -z "$$(eval echo \$$$$var)" ] && ! grep -q "^$$var=" .env; then \
			read -p "💭 $$var (required): " input; \
			if [ -n "$$input" ]; then \
				echo "$$var=$$input" >> .env; \
			else \
				echo "🚨 Error: $$var is required"; \
				exit 1; \
			fi; \
		else \
			if ! grep -q "^$$var=" .env; then \
				echo "$$var=$$(eval echo \$$$$var)" >> .env; \
			fi; \
		fi; \
	done;
	@ANON_ID=$$(hostname | { { md5sum 2>/dev/null || md5 2>/dev/null || shasum -a 256 2>/dev/null || sha256sum 2>/dev/null; } | awk '{print $$1}' || echo "unknown"; }) && \
	if ! grep -q "^POSTHOG_ID=" .env; then \
		echo "POSTHOG_ID=$$ANON_ID" >> .env; \
	fi;

.make:
	@mkdir -p .make

.make/poetry_install: .make poetry.lock
	poetry install
	@touch .make/poetry_install

poetry.lock: pyproject.toml
	@poetry lock --no-update
	@touch poetry.lock

Dockerfile: pyproject.toml .make
	@sed -e 's/^ARG EIDOLON_VERSION=.*/ARG EIDOLON_VERSION=${SDK_VERSION}/' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
	@echo "Updated Dockerfile with EIDOLON_VERSION=${SDK_VERSION}"

check-docker-daemon:
	@docker info >/dev/null 2>&1 || (echo "🚨 Error: Docker daemon is not running\n🛟 For help installing or running docker, visit https://docs.docker.com/get-docker/" >&2 && exit 1)

docker-serve: .env check-docker-daemon poetry.lock Dockerfile docker-compose.yml docker-build pull-webui
	docker compose up $(ARGS)

docker-compose.yml: Makefile
	@sed -e '/^  agent-server:/,/^  [^ ]/s/^    image: .*/    image: ${DOCKER_REPO_NAME}:latest/' docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml
	@echo "Updated docker-compose.yml with image ${DOCKER_REPO_NAME}:latest"

update:
	poetry add eidolon-ai-sdk@latest
	poetry lock --no-update
	$(MAKE) Dockerfile

sync:
	@if git remote | grep -q upstream; then \
		echo "upstream already exists"; \
	else \
		git remote add upstream https://github.com/eidolon-ai/agent-machine.git; \
		echo "upstream added"; \
	fi
	git fetch upstream
	git merge upstream/main --no-edit

k8s-operator: check-kubectl check-helm check-cluster-running verify-k8s-permissions check-install-operator
	@echo "K8s environment is ready. You can now deploy your application."

# Check if helm is available
check-helm:
	@which helm > /dev/null || (echo "helm is not installed. Please install it and try again." && exit 1)

# Check if kubectl is available
check-kubectl:
	@which kubectl > /dev/null || (echo "kubectl is not installed. Please install it and try again." && exit 1)

# Check if the cluster is running
check-cluster-running:
	@kubectl cluster-info > /dev/null 2>&1 || (echo "Kubernetes cluster is not running. Please start your cluster and try again." && exit 1)

# Verify K8s permissions
verify-k8s-permissions:
	@./k8s/verify_k8s -q || (echo "K8s permission verification failed. Please check your permissions and try again." && exit 1)

# Check if Eidolon operator is installed, install if not
check-install-operator:
	@if ! helm list | grep -q "eidolon"; then \
		echo "Eidolon operator not found. Installing..."; \
		helm repo add eidolon https://eidolonai.com/charts; \
		helm install eidolon eidolon-operator/eidolon-operator-chart || (echo "Failed to install Eidolon operator" && exit 1); \
	else \
		echo "Eidolon operator is already installed."; \
	fi

k8s-serve: k8s-server k8s-webui
	@echo "Press Ctrl+C to exit"
	@echo "------------------------------------------------------------------"
	@echo "Server is running at $$(./k8s/get_service_url.sh eidolon-ext-service)"
	@echo "WebUI is running at $$(./k8s/get_service_url.sh eidolon-webui-service)"
	@echo "------------------------------------------------------------------"
	kubectl logs -f \
		-l 'app in (eidolon, eidolon-webui)' \
		--all-containers=true \
		--prefix=true

k8s-server: check-cluster-running docker-build k8s-env
	@kubectl apply -f k8s/ephemeral_machine.yaml
	@kubectl apply -f resources/
	@kubectl apply -f k8s/eidolon-ext-service.yaml
	@echo "Waiting for eidolon-deployment to be ready..."
	@kubectl rollout status deployment/eidolon-deployment --timeout=60s
	@echo "Server Deployment is ready."

k8s-webui:
	@kubectl create configmap webui-apps-config --from-file=./webui.apps.json -o yaml --dry-run=client | kubectl apply -f -
	@kubectl apply -f k8s/webui.yaml
	@echo "Waiting for eidolon-webui to be ready..."
	@kubectl rollout status deployment/eidolon-webui-deployment --timeout=60s
	@echo "WebUI Deployment is ready."

k8s-env: .env
	@if [ ! -f .env ]; then echo ".env file not found!"; exit 1; fi
	@kubectl create secret generic eidolon --from-env-file=./.env --dry-run=client -o yaml | kubectl apply -f -

docker-build: poetry.lock Dockerfile
	@docker build -t $(DOCKER_REPO_NAME):latest .

pull-webui:
	@if ! docker image inspect eidolonai/webui:latest > /dev/null 2>&1; then \
		docker pull eidolonai/webui:latest; \
	fi
