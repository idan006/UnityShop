# ===================================================================
# Cross-platform Makefile for UnityExpress
# Works on Linux, macOS, Windows Git Bash, WSL
# ===================================================================

# -----------------------------
# Python detection
# -----------------------------
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
# Jest detection
# -----------------------------
JEST := $(shell \
	if command -v npx >/dev/null 2>&1; then echo "npx jest"; \
	elif command -v jest >/dev/null 2>&1; then echo "jest"; \
	else echo ""; fi \
)

# -----------------------------
# Colors (ANSI-safe using printf)
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
# Helm Chart
# -----------------------------
CHART := ./charts/unityexpress

# -----------------------------
# Docker images
# -----------------------------
IMAGES := unityexpress-api:local unityexpress-web:local

# ===================================================================
# Build Docker images
# ===================================================================
build:
	@printf "$(BLUE)==> Building Docker images locally$(NC)\n"
	docker build -t unityexpress-api:local ./api-server
	docker build -t unityexpress-web:local ./web-server
	@printf "$(GREEN)[OK] Build finished.$(NC)\n"

# ===================================================================
# Load images into Minikube
# ===================================================================
load:
	@printf "$(BLUE)==> Loading local images into Minikube$(NC)\n"
	@for img in $(IMAGES); do \
		printf "Loading %s...\n" "$$img"; \
		minikube image load $$img || true; \
	done
	@printf "$(GREEN)[OK] Images loaded into Minikube.$(NC)\n"

# ===================================================================
# Ensure CRDs exist (KEDA + Prometheus Operator)
# ===================================================================
ensure-crds:
	@printf "$(BLUE)==> Ensuring required CRDs exist...$(NC)\n"
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
	@printf "$(GREEN)[OK] CRDs confirmed.$(NC)\n"

# ===================================================================
# Deploy UnityExpress (atomic: build → load → crds → helm)
# ===================================================================
deploy: build load ensure-crds
	@printf "$(BLUE)==> Deploying UnityExpress via Helm$(NC)\n"
	helm upgrade --install unityexpress $(CHART) -n $(NS) --create-namespace
	@printf "$(GREEN)Deploy complete.$(NC)\n"

# ===================================================================
# Destroy environment
# ===================================================================
destroy:
	@printf "$(RED)==> Destroying UnityExpress...$(NC)\n"
	helm uninstall unityexpress -n $(NS) || true
	kubectl delete namespace $(NS) --ignore-not-found=true
	@printf "$(GREEN)Environment destroyed.$(NC)\n"

# ===================================================================
# Restart deployments
# ===================================================================
restart:
	@printf "$(BLUE)==> Restarting all deployments$(NC)\n"
	kubectl rollout restart deploy -n $(NS)
	@printf "$(GREEN)Restart completed.$(NC)\n"

# ===================================================================
# Logs
# ===================================================================
logs:
	@printf "$(BLUE)==> Logs: unityexpress-api$(NC)\n"
	kubectl logs -n $(NS) deploy/unityexpress-api --tail=200 || true
	@printf "$(BLUE)==> Logs: unityexpress-web$(NC)\n"
	kubectl logs -n $(NS) deploy/unityexpress-web --tail=200 || true
	@printf "$(BLUE)==> Logs: unityexpress-kafka$(NC)\n"
	kubectl logs -n $(NS) deploy/unityexpress-kafka -c kafka --tail=200 || true
	@printf "$(GREEN)Log output complete.$(NC)\n"

# ===================================================================
# Smoke Test
# ===================================================================
smoke:
	@printf "$(YELLOW)==> Running Smoke Test...$(NC)\n"
	$(PYTHON) ./scripts/smoke_test.py || { printf "$(RED)Smoke test FAILED$(NC)\n"; exit 1; }
	@printf "$(GREEN)Smoke test passed.$(NC)\n"

# ===================================================================
# Health Test
# ===================================================================
health:
	@printf "$(YELLOW)==> Running health verification...$(NC)\n"
	$(PYTHON) ./scripts/verify-health.py
	@printf "$(GREEN)Health check completed.$(NC)\n"

# ===================================================================
# Load Test
# ===================================================================
load-test:
	@printf "$(YELLOW)==> Running Load Test...$(NC)\n"
	$(PYTHON) ./scripts/load-test.py
	@printf "$(GREEN)Load test completed.$(NC)\n"

# ===================================================================
# Status
# ===================================================================
status:
	@printf "$(BLUE)==> Cluster services$(NC)\n"
	kubectl get pods,svc,hpa -n $(NS) -o wide

# ===================================================================
# Unit Tests
# ===================================================================
unitTests:
	@printf "$(BLUE)==> Running backend unit tests (Jest)...$(NC)\n"
	@if [ -z "$(JEST)" ]; then \
		printf "$(RED)[ERROR] Jest not installed. Run: npm install --save-dev jest$(NC)\n"; \
		exit 1; \
	fi
	$(JEST) --runInBand
	@printf "$(GREEN)Unit tests completed.$(NC)\n"

# ===================================================================
# Mock Tests
# ===================================================================
mock:
	@printf "$(BLUE)==> Running UI mock tests$(NC)\n"
	$(JEST) --config web-server/jest.config.js --runInBand
	@printf "$(GREEN)Mock tests completed.$(NC)\n"

# ===================================================================
# Full Test Suite
# ===================================================================
test-all:
	@printf "$(YELLOW)==> Running FULL TEST SUITE$(NC)\n"
	make unitTests
	make mock
	@printf "$(GREEN)All tests passed.$(NC)\n"

# ===================================================================
# Help
# ===================================================================
help:
	@printf "\n$(BLUE)UnityExpress Makefile Commands$(NC)\n"
	@printf "  $(GREEN)make deploy$(NC)      Deploy full environment\n"
	@printf "  $(GREEN)make destroy$(NC)     Destroy environment\n"
	@printf "  $(GREEN)make restart$(NC)     Restart deployments\n"
	@printf "  $(GREEN)make logs$(NC)        Show logs\n"
	@printf "  $(GREEN)make smoke$(NC)       Run smoke test\n"
	@printf "  $(GREEN)make health$(NC)      Run health test\n"
	@printf "  $(GREEN)make load-test$(NC)   Run load test\n"
	@printf "  $(GREEN)make status$(NC)      Show cluster status\n"
