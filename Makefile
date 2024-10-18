DOCKER_REPO_NAME ?= my-eidolon-project
VERSION := $(shell grep -m 1 '^version = ' pyproject.toml | awk -F '"' '{print $$2}')
WEBUI_TAG := latest
REQUIRED_ENVS := OPENAI_API_KEY
NAMESPACE ?= default

.PHONY: docker-serve _docker-serve .env sync update docker-build docker-push pull-webui k8s-operator check-kubectl check-helm check-cluster-running verify-k8s-permissions check-install-operator k8s-serve k8s-env k8s-mongo k8s-chroma test

ARGS ?=

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
	poetry lock --no-update
	@touch poetry.lock

Dockerfile: pyproject.toml .make poetry.lock
	@SDK_VERSION=$$(awk '/eidolon-ai-sdk/{getline; if ($$1 == "version") {gsub(/"|,/,"",$$3); print $$3; exit}}' poetry.lock); \
	sed -e 's/^ARG EIDOLON_VERSION=.*/ARG EIDOLON_VERSION='$${SDK_VERSION}'/' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile; \
	echo "Updated Dockerfile with EIDOLON_VERSION=$${SDK_VERSION}"

check-docker-daemon:
	@docker info >/dev/null 2>&1 || (echo "🚨 Error: Docker daemon is not running\n🛟 For help installing or running docker, visit https://docs.docker.com/get-docker/" >&2 && exit 1)

docker-serve: .env check-docker-daemon poetry.lock Dockerfile docker-compose.yml
	$(MAKE) -j4 _docker-serve ARGS=$(ARGS)

_docker-serve: docker-build pull-webui pull-mongo pull-chroma
	docker compose up $(ARGS)

docker-clean:
	docker compose down -v


docker-compose.yml: Makefile
	@sed -e '/^  agent-server:/,/^  [^ ]/s/^    image: .*/    image: ${DOCKER_REPO_NAME}:latest/' docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml
	@echo "Updated docker-compose.yml with image ${DOCKER_REPO_NAME}:latest"
	@sed -e 's|image: eidolonai/webui:.*|image: eidolonai/webui:$(WEBUI_TAG)|' docker-compose.yml > docker-compose.yml.tmp && mv docker-compose.yml.tmp docker-compose.yml
	@echo "Updated docker-compose.yml with image eidolonai/webui:$(WEBUI_TAG)"
	
	

update:
	poetry add --lock eidolon-ai-sdk@latest
	$(MAKE) Dockerfile

	@new_version=$$(curl -s https://raw.githubusercontent.com/eidolon-ai/eidolon/refs/heads/main/webui/package.json | grep -o '"version": "[^"]*"' | cut -d'"' -f4); \
	sed -e 's/^WEBUI_TAG := .*/WEBUI_TAG := '$$new_version'/' Makefile > Makefile.tmp && mv Makefile.tmp Makefile;
	$(MAKE) docker-compose.yml
	$(MAKE) k8s/webui.yaml


sync:
	@if git remote | grep -q upstream; then \
		echo "upstream already exists"; \
	else \
		git remote add upstream https://github.com/eidolon-ai/agent-machine.git; \
		echo "upstream added"; \
	fi
	git pull upstream main --no-edit --no-commit
	poetry lock --no-update
	$(MAKE) Dockerfile
	git add .
	- git commit -m "Sync with upstream"

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
	@echo "Server is running at $$(./k8s/get_service_url.sh eidolon-ext-service $(NAMESPACE))"
	@echo "WebUI is running at $$(./k8s/get_service_url.sh eidolon-webui-service $(NAMESPACE))"
	@echo "------------------------------------------------------------------"
	kubectl logs -f \
		-l 'app in (eidolon, eidolon-webui)' \
		--all-containers=true \
		--prefix=true \
		--namespace=$(NAMESPACE)

resources/machine.eidolon.yaml: Makefile
	@sed -e 's|image: .*|image: ${DOCKER_REPO_NAME}:latest|' \
		-e 's|imagePullPolicy: .*|imagePullPolicy: $(if $(DOCKER_REPO_URL),Always,Never)|' \
		resources/machine.eidolon.yaml > resources/machine.eidolon.yaml.tmp && mv resources/machine.eidolon.yaml.tmp resources/machine.eidolon.yaml


k8s-server: check-cluster-running docker-push k8s-env resources/machine.eidolon.yaml k8s-mongo k8s-chroma
	@kubectl apply -f resources/ --namespace=$(NAMESPACE)
	@kubectl apply -f k8s/eidolon-ext-service.yaml --namespace=$(NAMESPACE)
	@echo "Waiting for eidolon-deployment to be ready..."
	@kubectl rollout status deployment/eidolon-deployment --timeout=60s --namespace=$(NAMESPACE)
	@echo "Server Deployment is ready."

k8s-mongo:
	@kubectl apply -f k8s/mongo.yaml --namespace=$(NAMESPACE)
	@echo "Waiting for mongo to be ready..."
	@kubectl wait --for=condition=ready pod -l app=mongodb --timeout=60s --namespace=$(NAMESPACE)
	@echo "Mongo Deployment is ready."

k8s-chroma:
	@kubectl apply -f k8s/chroma.yaml --namespace=$(NAMESPACE)
	@echo "Waiting for chroma to be ready..."
	@kubectl wait --for=condition=ready pod -l app=chromadb --timeout=60s --namespace=$(NAMESPACE)
	@kubectl rollout status deployment/chromadb --timeout=60s --namespace=$(NAMESPACE)
	@echo "Chroma Deployment is ready."

k8s/webui.yaml: Makefile
	@sed -e 's|image: docker.io/eidolonai/webui:.*|image: docker.io/eidolonai/webui:$(WEBUI_TAG)|' k8s/webui.yaml > k8s/webui.yaml.tmp && mv k8s/webui.yaml.tmp k8s/webui.yaml


k8s-webui: k8s/webui.yaml
	@kubectl create configmap webui-apps-config --from-file=./webui.apps.json -o yaml --dry-run=client | kubectl apply -f - --namespace=$(NAMESPACE)
	@kubectl apply -f k8s/webui.yaml --namespace=$(NAMESPACE)
	@echo "Waiting for eidolon-webui to be ready..."
	@kubectl rollout status deployment/eidolon-webui-deployment --timeout=60s --namespace=$(NAMESPACE)
	@echo "WebUI Deployment is ready."

# Add this target to create the namespace if it doesn't exist
create-namespace:
	@kubectl get namespace $(NAMESPACE) || kubectl create namespace $(NAMESPACE)

# Update the k8s-env target to depend on create-namespace
k8s-env: create-namespace .env
	@if [ ! -f .env ]; then echo ".env file not found!"; exit 1; fi
	@kubectl create secret generic eidolon --from-env-file=./.env --dry-run=client -o yaml | kubectl apply -f - --namespace=$(NAMESPACE)

docker-build: poetry.lock Dockerfile
	@docker build -t $(DOCKER_REPO_NAME):latest .

docker-push: docker-build
	@if [ -n "$(DOCKER_REPO_URL)" ]; then \
		docker push $(DOCKER_REPO_NAME):latest; \
	fi


# docker compose spends extra time extracting images into the daemon, which we can avoid by pulling them ourselves
pull-webui:
	@if ! docker image inspect eidolonai/webui:latest > /dev/null 2>&1; then \
		docker pull eidolonai/webui:latest; \
	fi

pull-mongo:
	@if ! docker image inspect mongo > /dev/null 2>&1; then \
		docker pull mongo; \
	fi

pull-chroma:
	@if ! docker image inspect chromadb/chroma > /dev/null 2>&1; then \
		docker pull chromadb/chroma; \
	fi

k8s-clean:
	@kubectl delete -f resources/ -f k8s/eidolon-ext-service.yaml -f k8s/webui.yaml -f k8s/mongo.yaml -f k8s/chroma.yaml -n $(NAMESPACE)
