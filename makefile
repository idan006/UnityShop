# ===================================================================
# UnityExpress Makefile — Docker Desktop + Minikube (Docker Driver)
# ===================================================================

# UnityExpress Makefile — Docker Desktop + Minikube (Docker Driver)

# Simple Makefile targets for building images, loading into Minikube, and
# deploying via Helm. Uses plain echo instead of shell-specific color helpers
# so it is easier to run from different shells/platforms.

NS := unityexpress
CHART := ./charts/unityexpress
IMAGES := unityexpress-api:local unityexpress-web:local

# ===================================================================
# Docker Desktop Image Build
# ===================================================================
build:
	@echo "==> Building Docker images locally (Docker Desktop)"
	docker build -t unityexpress-api:local ./api-server
	docker build -t unityexpress-web:local ./web-server
	@echo "[OK] Images built locally."

# ===================================================================
# Load Images Into Minikube Docker Runtime
# ===================================================================
load:
	@echo "==> Loading images into Minikube"
	@echo "Loading unityexpress-api:local ..."
	minikube image load unityexpress-api:local || { echo "Failed to load unityexpress-api:local"; exit 1; }
	@echo "Loading unityexpress-web:local ..."
	minikube image load unityexpress-web:local || { echo "Failed to load unityexpress-web:local"; exit 1; }
	@echo "[OK] Images loaded into Minikube."

# ===================================================================
# Deploy With Helm
# ===================================================================
deploy: build load
	@echo "==> Ensuring required CRDs exist (KEDA + Prometheus Operator)..."

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

	@echo "[OK] CRDs confirmed."
	@echo "==> Deploying UnityExpress via Helm"

	helm upgrade --install unityexpress $(CHART) -n $(NS) --create-namespace

	@echo "[OK] Deployment finished."

	@echo "==> Waiting for gateway pod..."
	kubectl wait --for=condition=ready pod -l app=unityexpress-gateway -n $(NS) --timeout=120s || true

	@echo "==> Gateway URL:"
	@minikube service unityexpress-gateway -n $(NS) --url || \
	  @echo "Pods not ready yet. Run 'make url' later."

# ===================================================================
# Destroy all UnityExpress resources
# ===================================================================
destroy:
	@echo "==> Destroying UnityExpress"
	helm uninstall unityexpress -n $(NS) || true
	kubectl delete namespace $(NS) --ignore-not-found=true
	@echo "[OK] Environment destroyed."

# ===================================================================
# Restart Deployments
# ===================================================================
restart:
	@echo "==> Restarting deployments..."
	kubectl rollout restart deploy -n $(NS)
	@echo "[OK] Restart complete."

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
	@echo "==> Getting gateway URL"
	@minikube service unityexpress-gateway -n $(NS) --url

# ===================================================================
# Open Browser
# ===================================================================

open:
	@echo "==> Opening UI in browser"
	minikube service unityexpress-gateway -n $(NS)

# ===================================================================
# Smoke Test
# ===================================================================
smoke:
	@echo "==> Running Smoke Test"
	python ./scripts/smoke_test.py || { echo "Smoke test failed"; exit 1; }
	@echo "[OK] Smoke test passed."

# ===================================================================
# Status
# ===================================================================
status:
	kubectl get pods,svc,hpa -n $(NS) -o wide

install-keda:
	helm repo add kedacore https://kedacore.github.io/charts
	helm upgrade --install keda kedacore/keda -n keda --create-namespace

# ===================================================================
# Help
# ===================================================================

help:
	@echo "\nUnityExpress Makefile Commands:\n"
	@echo "  make deploy        Build + Load + Deploy"
	@echo "  make destroy       Delete environment"
	@echo "  make restart       Restart deployments"
	@echo "  make logs          Show service logs"
	@echo "  make url           Get gateway URL"
	@echo "  make open          Open UI in browser"
	@echo "  make smoke         Run smoke test"
	@echo "  make status        Show cluster status"
	@echo "  make unitTests     Run backend tests"
	@echo "  make mock          Run UI mock tests\n"
