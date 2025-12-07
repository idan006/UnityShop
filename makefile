# ===================================================================
# Cross-platform Makefile for UnityExpress
# Works on Linux, macOS, Windows Git Bash, WSL
# ===================================================================

# -----------------------------
# Cross-platform Python detection
# -----------------------------
# Checks: 1. python3, 2. python, 3. py (Windows launcher)
PYTHON := $(shell \
	if command -v python3 >/dev/null 2>&1; then echo python3; \
	elif command -v python >/dev/null 2>&1; then echo python; \
	elif command -v py >/dev/null 2>&1; then echo py; \
	else echo ""; fi \
)

ifeq ($(PYTHON),)
$(error No Python interpreter found. Install Python before running make targets)
endif

# -----------------------------
# Detect Jest test runner
# -----------------------------
JEST := $(shell \
	if command -v npx >/dev/null 2>&1; then echo "npx jest"; \
	elif command -v jest >/dev/null 2>&1; then echo "jest"; \
	else echo ""; fi \
)

ifeq ($(JEST),)
$(warning Jest not found. Install with: npm install --save-dev jest)
endif

# -----------------------------
# Colors (ANSI)
# -----------------------------
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[1;34m
NC     := \033[0m

# -----------------------------
# Kubernetes Namespace
# -----------------------------
NS := unityexpress

# -----------------------------
# Helm Chart Path
# -----------------------------
CHART := ./charts/unityexpress

IMAGES := unityexpress-api:local unityexpress-web:local

build:
	@echo "$(BLUE)==> Building Docker images locally$(NC)"
	docker build -t unityexpress-api:local ./api-server
	docker build -t unityexpress-web:local ./web-server

load:
	@echo "$(BLUE)==> Loading local images into Minikube$(NC)"
	for img in $(IMAGES); do \
		echo "Loading $$img ..."; \
		minikube image load $$img; \
	done
	@echo "$(GREEN)Images successfully loaded into Minikube.$(NC)"
	
# ===================================================================
# Deploy UnityExpress Shop
# ===================================================================
deploy: build load
	@echo "$(BLUE)==> Ensuring required CRDs exist...$(NC)"
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
	@echo "$(GREEN)[OK] CRDs confirmed.$(NC)"

	@echo "$(BLUE)==> Loading local Docker images into Minikube$(NC)"
	for img in unityexpress-api:local unityexpress-web:local; do \
	  echo "Loading $$img ..."; \
	  minikube image load $$img || true; \
	done

	@echo "$(GREEN)Images loaded.$(NC)"

	@echo "$(BLUE)==> Deploying UnityExpress via Helm$(NC)"
	helm upgrade --install unityexpress $(CHART) -n $(NS) --create-namespace
	@echo "$(GREEN)Deploy complete.$(NC)"


# ===================================================================
# Destroy environment
# ===================================================================
destroy:
	@echo "$(RED)==> Destroying UnityExpress...$(NC)"
	helm uninstall unityexpress -n $(NS) || true
	kubectl delete namespace $(NS) --ignore-not-found=true
	@echo "$(GREEN)Environment destroyed.$(NC)"

# ===================================================================
# Restart deployments
# ===================================================================
restart:
	@echo "$(BLUE)==> Restarting all deployments in $(NS)...$(NC)"
	kubectl rollout restart deploy -n $(NS)
	@echo "$(GREEN)Restart completed.$(NC)"

# ===================================================================
# Logs
# ===================================================================
logs:
	@echo "$(BLUE)==> Logs: unityexpress-api$(NC)"
	kubectl logs -n $(NS) deploy/unityexpress-api --tail=200 || true
	@echo "$(BLUE)==> Logs: unityexpress-web$(NC)"
	kubectl logs -n $(NS) deploy/unityexpress-web --tail=200 || true
	@echo "$(BLUE)==> Logs: unityexpress-kafka$(NC)"
	kubectl logs -n $(NS) deploy/unityexpress-kafka -c kafka --tail=200 || true
	@echo "$(GREEN)Log output complete.$(NC)"

# ===================================================================
# Smoke Test
# ===================================================================
smoke:
	@echo "$(YELLOW)==> Running Smoke Test...$(NC)"
	$(PYTHON) ./scripts/smoke_test.py || { echo "$(RED)Smoke test failed$(NC)"; exit 1; }
	@echo "$(GREEN)Smoke test executed.$(NC)"

# ===================================================================
# Health Test
# ===================================================================
health:
	@echo "$(YELLOW)==> Running health verification...$(NC)"
	$(PYTHON) ./scripts/verify-health.py
	@echo "$(GREEN)Health check completed.$(NC)"

# ===================================================================
# Load Test
# ===================================================================
load-test:
	@echo "$(YELLOW)==> Running Load Test...$(NC)"
	$(PYTHON) ./scripts/load-test.py
	@echo "$(GREEN)Load test completed.$(NC)"

# ===================================================================
# Status
# ===================================================================
status:
	@echo "$(BLUE)==> Cluster services:$(NC)"
	kubectl get pods,svc,hpa -n $(NS) -o wide

# ===================================================================
#  Unit Tests (Backend)
# ===================================================================
unitTests:
	@echo "$(BLUE)==> Running backend unit tests (Jest)...$(NC)"
	@if [ -z "$(JEST)" ]; then \
		echo "$(RED)[ERROR] Jest is not installed. Run: npm install --save-dev jest$(NC)"; \
		exit 1; \
	fi
	$(JEST) --runInBand
	@echo "$(GREEN)Unit tests completed.$(NC)"

# ===================================================================
#  Mock Tests (UI / API mock layer)
# ===================================================================
mock:
	@echo "$(BLUE)==> Running UI mock tests...$(NC)"
	@if [ -z "$(JEST)" ]; then \
		echo "$(RED)[ERROR] Jest missing. Install with: npm install --save-dev jest$(NC)"; \
		exit 1; \
	fi
	$(JEST) --config web/jest.config.js --runInBand
	@echo "$(GREEN)Mock tests completed.$(NC)"

# ===================================================================
#  Full Test Suite (Backend + Web)
# ===================================================================
test-all:
	@echo "$(YELLOW)==> Running FULL TEST SUITE (backend + UI)...$(NC)"
	make unitTests
	make mock
	@echo "$(GREEN)All tests passed.$(NC)"


# ===================================================================
#  Coverage Reports
# ===================================================================
coverage:
	@echo "$(BLUE)==> Running coverage for backend + UI...$(NC)"
	$(JEST) --coverage --config unityexpress-api/jest.config.js
	$(JEST) --coverage --config web/jest.config.js
	@echo "$(GREEN)Coverage complete. Reports in coverage/$(NC)"


# ===================================================================
#  Watch Modes
# ===================================================================
watch:
	@echo "$(BLUE)==> Jest watch mode (backend)...$(NC)"
	$(JEST) --watch --config unityexpress-api/jest.config.js

watch-ui:
	@echo "$(BLUE)==> Jest watch mode (UI)...$(NC)"
	$(JEST) --watch --config web/jest.config.js
	
# ===================================================================
# Help
# ===================================================================
help:
	@echo ""
	@echo "$(BLUE)UnityExpress Makefile Commands$(NC)"
	@echo "  $(GREEN)make deploy$(NC)      Deploy system"
	@echo "  $(GREEN)make destroy$(NC)     Destroy environment"
	@echo "  $(GREEN)make restart$(NC)     Restart all deployments"
	@echo "  $(GREEN)make logs$(NC)        Show logs for services"
	@echo "  $(GREEN)make smoke$(NC)       Run smoke test"
	@echo "  $(GREEN)make health$(NC)      Run health test"
	@echo "  $(GREEN)make load-test$(NC)   Run load test"
	@echo "  $(GREEN)make status$(NC)      Show cluster state"
	@echo ""