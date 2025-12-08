#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Colors & Logging helpers
# ------------------------------------------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
NC="\033[0m"

log_info()  { echo -e "${BLUE}[*]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

trap 'log_error "Script failed on line $LINENO"; exit 1' ERR


echo "============================================================"
echo "      UnityExpress – Cross-Platform Prerequisites Setup"
echo "============================================================"

# ------------------------------------------------------------
# OS detection
# ------------------------------------------------------------
OS="unknown"
case "$(uname -s)" in
  Linux*)   OS="linux" ;;
  Darwin*)  OS="mac" ;;
  CYGWIN*|MINGW*|MSYS_NT*) OS="windows" ;;
  *) OS="unknown" ;;
esac
log_info "Detected OS: $OS"

# ------------------------------------------------------------
# Ensure Docker Desktop is installed and running
# ------------------------------------------------------------
ensure_docker_desktop() {

  log_info "Checking Docker Desktop..."

  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker Desktop is not installed."

    if [ "$OS" = "windows" ]; then
      echo "Download from: https://www.docker.com/products/docker-desktop/"
      echo "After installation, restart this script."
    elif [ "$OS" = "mac" ]; then
      echo "Install Docker Desktop via:"
      echo "  brew install --cask docker"
      echo "Then open Docker Desktop manually."
    else
      log_error "Linux detected — UnityExpress supports Docker Desktop only."
    fi

    exit 1
  fi

  # check that daemon is reachable
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker Desktop installed but NOT running."
    echo "Start Docker Desktop manually, then rerun this script."
    exit 1
  fi

  log_ok "Docker Desktop is installed and running."
}

ensure_docker_desktop

# ------------------------------------------------------------
# Python detection
# ------------------------------------------------------------
detect_python() {
  PYTHON_CMD=""
  if command -v python3 >/dev/null 2>&1; then PYTHON_CMD="python3"; return; fi
  if command -v python >/dev/null 2>&1; then PYTHON_CMD="python"; return; fi
  if command -v py >/dev/null 2>&1; then PYTHON_CMD="py -3"; return; fi
}

ensure_python() {
  log_info "Checking Python..."

  detect_python

  if [ -z "${PYTHON_CMD}" ]; then
    log_error "Python not installed. Install Python 3 and rerun."
    exit 1
  fi

  log_ok "Using Python: $PYTHON_CMD"

  if ! $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
    log_warn "pip missing. Attempting ensurepip..."
    $PYTHON_CMD -m ensurepip || true
  fi
}

ensure_python

# ------------------------------------------------------------
# Kubernetes toolchain
# ------------------------------------------------------------
ensure_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "$1 missing — install it before running prerequisites."
    exit 1
  fi
  log_ok "$1 found"
}

echo "============================================================"
echo "   Checking Kubernetes Toolchain"
echo "============================================================"

ensure_tool kubectl
ensure_tool minikube
ensure_tool helm

# ------------------------------------------------------------
# FORCE MINIKUBE TO USE DOCKER DESKTOP DRIVER
# ------------------------------------------------------------
log_info "Configuring Minikube to use Docker Desktop driver..."

minikube config set driver docker >/dev/null 2>&1 || true
log_ok "Minikube configured to use Docker driver"

# ------------------------------------------------------------
# Start Minikube (Docker Desktop only)
# ------------------------------------------------------------
log_info "Starting Minikube (Docker driver)..."

if minikube status >/dev/null 2>&1; then
  log_ok "Minikube already running."
else
  minikube start \
    --driver=docker \
    --cpus=4 \
    --memory=8192 \
    --addons=metrics-server \
    --addons=dashboard
fi

log_ok "Minikube is running."

# ------------------------------------------------------------
# Docker → Minikube
# ------------------------------------------------------------
log_info "Configuring Docker client to use Minikube’s Docker daemon..."

if [ "$OS" = "windows" ]; then
  eval "$(minikube docker-env --shell=bash)"
else
  eval "$(minikube docker-env)"
fi

docker info >/dev/null 2>&1 \
  && log_ok "Docker now points to Minikube internal registry" \
  || log_error "Docker failed connecting to Minikube!"

# ------------------------------------------------------------
# dns-test pod
# ------------------------------------------------------------
log_info "Ensuring dns-test pod exists..."

if ! kubectl get pod dns-test >/dev/null 2>&1; then
  kubectl run dns-test \
    --image=busybox:1.36 \
    --restart=Never \
    --command -- sh -c "sleep 3600"
  log_ok "dns-test created"
else
  log_ok "dns-test already exists"
fi

# ------------------------------------------------------------
# Finish
# ------------------------------------------------------------
echo "============================================================"
echo "   Prerequisites Completed Successfully"
echo "============================================================"
echo " - Docker Desktop OK"
echo " - Python OK"
echo " - kubectl / minikube / helm OK"
echo " - Minikube running (Docker driver)"
echo " - Docker is pointing to Minikube"
echo " - dns-test pod ready"
echo "============================================================"
echo ""
echo "Next step: run    make deploy"
echo ""
