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

# ===================================================================
# Deploy UnityExpress
# ===================================================================
deploy:
	@echo "$(BLUE)==> Deploying UnityExpress...$(NC)"
	helm upgrade --install unityexpress $(CHART) -n $(NS) --create-namespace
	@echo "$(GREEN)Deployment completed.$(NC)"

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
	# **IMPORTANT**: Ensure the script file name is correct (e.g., smoke-test.py vs smoke_test.py)
	$(PYTHON) ./scripts/smoke-test.py
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