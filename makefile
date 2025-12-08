# ===================================================================
# UnityExpress Makefile — Docker Desktop + Minikube (Docker Driver)
# ===================================================================

# -----------------------------
# Cross-platform Python detection
# -----------------------------
PYTHON := $(shell \
	if command -v python3 >/dev/null 2>&1; then echo python3; \
	elif command -v python >/dev/null 2>&1; then echo python; \
	elif command -v py >/dev/null 2>&1; then echo py -3; \
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
# ANSI colors (Windows-safe)
# -----------------------------
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[1;34m
NC     := \033[0m

# -----------------------------
# Variables
# -----------------------------
NS := unityexpress
CHART := ./charts/unityexpress
IMAGES := unityexpress-api:local unityexpress-web:local

# ===================================================================
# Build Docker images using Docker Desktop
# ===================================================================
build:
	@echo "$(BLUE)==> Building Docker images locally (Docker Desktop)$(NC)"
	docker build -t unityexpress-api:local ./api-server
	docker build -t unityexpress-web:local ./web-server
	@echo "$(GREEN)[OK] Images built locally.$(NC)"

# ===================================================================
# Load images into Minikube Docker environment
# ===================================================================
load:
	@echo "$(BLUE)==> Loading images into Minikube$(NC)"
	for img in $(IMAGES); do \
		echo "Loading $$img ..."; \
		minikube image load $$img || { echo "$(RED)Failed to load $$img$(NC)"; exit 1; }; \
	done
	@echo "$(GREEN)[OK] Images loaded into Minikube.$(NC)"

# ===================================================================
# Deploy using Helm
# ===================================================================
deploy: build load
	@echo "$(BLUE)==> Ensuring required CRDs exist (KEDA + Prometheus Operator)...$(NC)"

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

	@echo "$(BLUE)==> Deploying UnityExpress via Helm$(NC)"
	helm upgrade --install unityexpress $(CHART) -n $(NS) --create-namespace
	@echo "$(GREEN)[OK] Deployment finished.$(NC)"
	@echo ""
	@echo "$(BLUE)==> Gateway URL:$(NC)"
	@minikube service unityexpress-gateway -n $(NS) --url
	@echo ""

# ===================================================================
# Destroy everything
# ===================================================================
destroy:
	@echo "$(RED)==> Destroying UnityExpress deployment$(NC)"
	helm uninstall unityexpress -n $(NS) || true
	kubectl delete namespace $(NS) --ignore-not-found=true
	@echo "$(GREEN)[OK] Environment destroyed.$(NC)"

# ===================================================================
# Restart pods
# ===================================================================
restart:
	@echo "$(BLUE)==> Restarting all deployments in $(NS)...$(NC)"
	kubectl rollout restart deploy -n $(NS)
	@echo "$(GREEN)[OK] Restart done.$(NC)"

# ===================================================================
# Logs
# ===================================================================
logs:
	kubectl logs -n $(NS) deploy/unityexpress-api --tail=200 || true
	kubectl logs -n $(NS) deploy/unityexpress-web --tail=200 || true
	kubectl logs -n $(NS) deploy/unityexpress-kafka -c kafka --tail=200 || true

# ===================================================================
# Get UI URL
# ===================================================================
url:
	@echo "$(BLUE)==> Getting gateway URL...$(NC)"
	@minikube service unityexpress-gateway -n $(NS) --url

# ===================================================================
# Open UI in browser
# ===================================================================
open:
	@echo "$(BLUE)==> Opening UI in browser...$(NC)"
	minikube service unityexpress-gateway -n $(NS)

# ===================================================================
# Smoke Test
# ===================================================================
smoke:
	@echo "$(YELLOW)==> Running Smoke Test$(NC)"
	$(PYTHON) ./scripts/smoke_test.py || { echo "$(RED)Smoke test failed$(NC)"; exit 1; }
	@echo "$(GREEN)[OK] Smoke test passed.$(NC)"

# ===================================================================
# Status Overview
# ===================================================================
status:
	kubectl get pods,svc,hpa -n $(NS) -o wide

# ===================================================================
# Unit Tests
# ===================================================================
unitTests:
	@if [ -z "$(JEST)" ]; then echo "$(RED)Jest missing$(NC)"; exit 1; fi
	$(JEST) --runInBand
	@echo "$(GREEN)[OK] Backend unit tests completed.$(NC)"

# ===================================================================
# UI Mock Tests
# ===================================================================
mock:
	@if [ -z "$(JEST)" ]; then echo "$(RED)Jest missing$(NC)"; exit 1; fi
	$(JEST) --config web/jest.config.js --runInBand
	@echo "$(GREEN)[OK] Mock tests completed.$(NC)"

# ===================================================================
# Help Menu
# ===================================================================
help:
	@echo ""
	@echo "UnityExpress Makefile Commands:"
	@echo "  make deploy        Build + Load + Deploy to Minikube"
	@echo "  make destroy       Delete environment"
	@echo "  make restart       Restart all deployments"
	@echo "  make logs          Show logs"
	@echo "  make url           Get gateway URL"
	@echo "  make open          Open UI in browser"
	@echo "  make smoke         Run smoke test"
	@echo "  make status        Show cluster status"
	@echo "  make unitTests     Run backend tests"
	@echo "  make mock          Run UI mock tests"
	@echo ""