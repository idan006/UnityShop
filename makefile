# ===================================================================
# UnityExpress Makefile — Docker Desktop + Minikube (Docker Driver)
# ===================================================================

SHELL := /bin/bash

# Universal ANSI color support (works on Linux, macOS, Windows Git Bash, WSL)
BLUE  := $(shell printf "\033[1;34m")
GREEN := $(shell printf "\033[0;32m")
YELLOW:= $(shell printf "\033[1;33m")
RED   := $(shell printf "\033[0;31m")
NC    := $(shell printf "\033[0m")

ECHO := printf

# -----------------------------
# Cross-platform Python detection
# -----------------------------
PYTHON := $(shell \
	if command -v python3 >/dev/null 2>&1; then echo python3; \
	elif command -v python >/dev/null 2>&1; then echo python; \
	elif command -v py >/dev/null 2>&1; then echo "py -3"; \
	else echo ""; fi \
)

ifeq ($(PYTHON),)
$(error No Python interpreter found. Install Python before running make targets)
endif

# -----------------------------
# Jest runner detection
# -----------------------------
JEST := $(shell \
	if command -v npx >/dev/null 2>&1; then echo "npx jest"; \
	elif command -v jest >/dev/null 2>&1; then echo "jest"; \
	else echo ""; fi \
)

# -----------------------------
# Variables
# -----------------------------
NS := unityexpress
CHART := ./charts/unityexpress
IMAGES := unityexpress-api:local unityexpress-web:local

# ===================================================================
# Docker Desktop Image Build
# ===================================================================
build:
	@$(ECHO) "$(BLUE)==> Building Docker images locally (Docker Desktop)$(NC)\n"
	docker build -t unityexpress-api:local ./api-server
	docker build -t unityexpress-web:local ./web-server
	@$(ECHO) "$(GREEN)[OK] Images built locally.$(NC)\n"

# ===================================================================
# Load Images Into Minikube Docker Runtime
# ===================================================================
load:
	@$(ECHO) "$(BLUE)==> Loading images into Minikube$(NC)\n"
	for img in $(IMAGES); do \
		echo "Loading $$img ..."; \
		minikube image load $$img || { echo "$(RED)Failed to load $$img$(NC)"; exit 1; }; \
	done
	@$(ECHO) "$(GREEN)[OK] Images loaded into Minikube.$(NC)\n"

# ===================================================================
# Deploy With Helm
# ===================================================================
deploy: build load
	@$(ECHO) "$(BLUE)==> Ensuring required CRDs exist (KEDA + Prometheus Operator)...$(NC)\n"

	kubectl get crd scaledobjects.keda.sh >/dev/null 2>&1 || \
	    kubectl apply -f https://raw.githubusercontent.com/kedacore/keda/v2.14.0/config/crd/bases/keda.sh_scaledobjects.yaml

	kubectl get crd triggerauthentications.keda.sh >/dev/null 2>&1 || \
	    kubectl apply -f https://raw.githubusercontent.com/kedacore/keda/v2.14.0/config/crd/bases/keda.sh_triggerauthentications.yaml

	kubectl get crd clustertriggerauthentications.keda.sh >/dev/null 2>&1 || \
	    kubectl apply -f https://raw.githubusercontent.com/kedacore/keda/v2.14.0/config/crd/bases/keda.sh_clustertriggerauthentications.yaml

	kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1 || \
	    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.74.0/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

	kubectl get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1 || \
	    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/v0.74.0/example/prometheus-operator-crd/monitoring.coreos.com_podmonitors.yaml

	@$(ECHO) "$(GREEN)[OK] CRDs confirmed.$(NC)\n"
	@$(ECHO) "$(BLUE)==> Deploying UnityExpress via Helm$(NC)\n"

	helm upgrade --install unityexpress $(CHART) -n $(NS) --create-namespace

	@$(ECHO) "$(GREEN)[OK] Deployment finished.$(NC)\n"

	@$(ECHO) "$(BLUE)==> Waiting for gateway pod...$(NC)\n"
	kubectl wait --for=condition=ready pod -l app=unityexpress-gateway -n $(NS) --timeout=120s || true

	@$(ECHO) "$(BLUE)==> Gateway URL:$(NC)\n"
	@minikube service unityexpress-gateway -n $(NS) --url || \
	  $(ECHO) "$(YELLOW)Pods not ready yet. Run 'make url' later.$(NC)\n"

# ===================================================================
# Destroy all UnityExpress resources
# ===================================================================
destroy:
	@$(ECHO) "$(RED)==> Destroying UnityExpress$(NC)\n"
	helm uninstall unityexpress -n $(NS) || true
	kubectl delete namespace $(NS) --ignore-not-found=true
	@$(ECHO) "$(GREEN)[OK] Environment destroyed.$(NC)\n"

# ===================================================================
# Restart Deployments
# ===================================================================
restart:
	@$(ECHO) "$(BLUE)==> Restarting deployments...$(NC)\n"
	kubectl rollout restart deploy -n $(NS)
	@$(ECHO) "$(GREEN)[OK] Restart complete.$(NC)\n"

# ===================================================================
# Logs
# ===================================================================
logs:
	kubectl logs -n $(NS) deploy/unityexpress-api --tail=200 || true
	kubectl logs -n $(NS) deploy/unityexpress-web --tail=200 || true
	kubectl logs -n $(NS) deploy/unityexpress-kafka -c kafka --tail=200 || true

# ===================================================================
# Get Gateway URL
# ===================================================================
url:
	@$(ECHO) "$(BLUE)==> Getting gateway URL$(NC)\n"
	@minikube service unityexpress-gateway -n $(NS) --url

# ===================================================================
# Open Browser
# ===================================================================
open:
	@$(ECHO) "$(BLUE)==> Opening UI in browser$(NC)\n"
	minikube service unityexpress-gateway -n $(NS)

# ===================================================================
# Smoke Test
# ===================================================================
smoke:
	@$(ECHO) "$(YELLOW)==> Running Smoke Test$(NC)\n"
	$(PYTHON) ./scripts/smoke_test.py || { $(ECHO) "$(RED)Smoke test failed$(NC)\n"; exit 1; }
	@$(ECHO) "$(GREEN)[OK] Smoke test passed.$(NC)\n"

# ===================================================================
# Status
# ===================================================================
status:
	kubectl get pods,svc,hpa -n $(NS) -o wide

# ===================================================================
# Helm Template Tests
# ===================================================================
test-templates:
	@$(ECHO) "$(BLUE)==> Helm lint$(NC)\n"
	helm lint $(CHART)
	@$(ECHO) "$(GREEN)[OK] Lint passed.$(NC)\n"

	@$(ECHO) "$(BLUE)==> Rendering templates$(NC)\n"
	helm template unityexpress $(CHART) -n $(NS) > /tmp/rendered-templates.yaml
	@$(ECHO) "$(GREEN)[OK] Templates saved to /tmp/rendered-templates.yaml$(NC)\n"

# ===================================================================
# Unit Tests
# ===================================================================
unitTests:
	@if [ -z "$(JEST)" ]; then $(ECHO) "$(RED)Jest missing$(NC)\n"; exit 1; fi
	$(JEST) --runInBand
	@$(ECHO) "$(GREEN)[OK] Unit tests passed.$(NC)\n"

# ===================================================================
# Mock Tests
# ===================================================================
mock:
	@if [ -z "$(JEST)" ]; then $(ECHO) "$(RED)Jest missing$(NC)\n"; exit 1; fi
	$(JEST) --config web/jest.config.js --runInBand
	@$(ECHO) "$(GREEN)[OK] Mock tests completed.$(NC)\n"

# ===================================================================
# Help
# ===================================================================
help:
	@$(ECHO) "\nUnityExpress Makefile Commands:\n"
	@$(ECHO) "  make deploy        Build + Load + Deploy"
	@$(ECHO) "  make destroy       Delete environment"
	@$(ECHO) "  make restart       Restart deployments"
	@$(ECHO) "  make logs          Show service logs"
	@$(ECHO) "  make url           Get gateway URL"
	@$(ECHO) "  make open          Open UI in browser"
	@$(ECHO) "  make smoke         Run smoke test"
	@$(ECHO) "  make status        Show cluster status"
	@$(ECHO) "  make unitTests     Run backend tests"
	@$(ECHO) "  make mock          Run UI mock tests\n"
