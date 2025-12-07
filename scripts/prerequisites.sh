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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "============================================================"
echo "        UnityExpress - Cross-Platform local Installer"
echo "============================================================"

# ------------------------------------------------------------
# OS detection
# ------------------------------------------------------------
OS="unknown"
case "$(uname -s)" in
  Linux*)   OS="linux" ;;
  Darwin*)  OS="mac" ;;
  CYGWIN*|MINGW*|MSYS_NT*) OS="windows" ;;
  *)        OS="unknown" ;;
esac

log_info "Detected OS: $OS"

# ------------------------------------------------------------
# Python detection and installation
# ------------------------------------------------------------
detect_python() {
  PYTHON_CMD=""
  if [ "$OS" = "windows" ]; then
    if command -v py >/dev/null 2>&1; then PYTHON_CMD="py -3"; return; fi
    if command -v python3 >/dev/null 2>&1; then PYTHON_CMD="python3"; return; fi
    if command -v python >/dev/null 2>&1; then PYTHON_CMD="python"; return; fi
  else
    if command -v python3 >/dev/null 2>&1; then PYTHON_CMD="python3"; return; fi
    if command -v python >/dev/null 2>&1; then PYTHON_CMD="python"; return; fi
  fi
}

install_python_windows() {
  log_warn "Python not found. Installing with Chocolatey..."
  if ! command -v choco >/dev/null 2>&1; then
    log_error "Chocolatey missing. Install from https://chocolatey.org/"
    exit 1
  fi
  choco install -y python
  log_ok "Python installed."
}

install_python_unix() {
  log_warn "Python not found. Installing..."
  if [ "$OS" = "mac" ]; then
    if ! command -v brew >/dev/null 2>&1; then
      log_error "Homebrew missing. Install manually from python.org"
      exit 1
    fi
    brew install python
  else
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update || true
      sudo apt-get install -y python3 python3-pip
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y python3
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y python3
    else
      log_error "No supported package manager found. Install manually."
      exit 1
    fi
  fi
}

ensure_python() {
  log_info "Checking Python availability..."
  detect_python

  if [ -z "${PYTHON_CMD}" ]; then
    if [ "$OS" = "windows" ]; then install_python_windows
    else install_python_unix
    fi
    detect_python
    if [ -z "${PYTHON_CMD}" ]; then
      log_error "Python still missing after installation attempt."
      exit 1
    fi
  fi

  log_ok "Using Python: $PYTHON_CMD"

  if ! $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
    log_warn "pip missing. Bootstrapping..."
    $PYTHON_CMD -m ensurepip || true
  fi
}

# ------------------------------------------------------------
# Kubernetes toolchain validation (kubectl, minikube, helm)
# ------------------------------------------------------------
ensure_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    log_ok "$name found"
  else
    log_error "$name missing — install it before running prerequisites."
    exit 1
  fi
}

ensure_k8s_tools() {
  echo "============================================================"
  echo "   Checking Kubernetes Toolchain"
  echo "============================================================"

  ensure_tool kubectl
  ensure_tool minikube
  ensure_tool helm
}

# ------------------------------------------------------------
# Minikube start / repair
# ------------------------------------------------------------
select_driver() {
  if command -v VBoxManage >/dev/null 2>&1; then
    echo "virtualbox"
  elif command -v docker >/dev/null 2>&1; then
    echo "docker"
  else
    echo ""
  fi
}

start_minikube() {
  echo "============================================================"
  echo "   Starting Minikube"
  echo "============================================================"

  local DRIVER
  DRIVER=$(select_driver)

  if [ -z "$DRIVER" ]; then
    log_error "No Minikube drivers available (VirtualBox or Docker)."
    exit 1
  fi

  log_info "Selected driver: $DRIVER"

  if ! minikube status >/dev/null 2>&1; then
    log_warn "Minikube not running. Starting fresh..."
    minikube delete || true
    minikube start \
      --driver="$DRIVER" \
      --cpus=4 \
      --memory=8192 \
      --addons=metrics-server \
      --addons=dashboard
  fi

  log_ok "Minikube is running."
}

# ------------------------------------------------------------
# Configure Docker to use Minikube Docker daemon
# ------------------------------------------------------------
configure_docker() {
  echo "============================================================"
  echo "   Configuring Docker for Minikube"
  echo "============================================================"

  case "$OS" in
    linux|mac)
      eval "$(minikube docker-env)"
      ;;
    windows)
      eval "$(minikube docker-env --shell=bash)"
      ;;
    *)
      log_error "Unsupported OS for docker-env"
      exit 1
      ;;
  esac

  if docker info >/dev/null 2>&1; then
    log_ok "Docker now points to Minikube"
  else
    log_error "Docker failed to connect to Minikube."
    echo "Run manually (PowerShell):"
    echo "  minikube -p minikube docker-env | Invoke-Expression"
    exit 1
  fi
}

# ------------------------------------------------------------
# Ensure dns-test pod
# ------------------------------------------------------------
ensure_dns_test() {
  echo "============================================================"
  echo "   Ensuring dns-test pod"
  echo "============================================================"

  if kubectl get pod dns-test >/dev/null 2>&1; then
    log_ok "dns-test already exists"
    return
  fi

  log_info "Creating dns-test..."
  kubectl run dns-test \
    --image=busybox:1.36 \
    --restart=Never \
    --command -- sh -c "sleep 3600" || log_warn "dns-test creation failed"

  log_ok "dns-test pod ready"
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
ensure_python
ensure_k8s_tools
start_minikube
configure_docker
ensure_dns_test

log_info "Exposing Minikube services to localhost..."
minikube tunnel >/dev/null 2>&1 &

eval $(minikube docker-env --shell=bash)


echo "============================================================"
echo "   Prerequisites completed successfully"
echo "============================================================"
echo " - Python ready"
echo " - kubectl / minikube / helm OK"
echo " - Docker → Minikube configured"
echo " - dns-test pod available"
echo "============================================================"
echo ""
echo "Run:  make deploy"
echo ""

echo "UI will be available at:  http://localhost:30090"
echo "API willl be available at: http://localhost:30090/api"

