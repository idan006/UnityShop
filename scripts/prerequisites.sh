#!/usr/bin/env bash

# Disable strict error checking for compatibility
set -u

# ------------------------------------------------------------
# Colors & Logging helpers
# ------------------------------------------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[0;36m"
NC="\033[0m"

log_info()    { printf "${BLUE}[*]${NC} %s\n" "$*"; }
log_ok()      { printf "${GREEN}[✓]${NC} %s\n" "$*"; }
log_warn()    { printf "${YELLOW}[!]${NC} %s\n" "$*"; }
log_error()   { printf "${RED}[✗]${NC} %s\n" "$*"; }
log_header()  { printf "${CYAN}▶ %s${NC}\n" "$*"; }

echo "============================================================"
echo "      UnityExpress – Cross-Platform Prerequisites Setup"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# OS detection
# ------------------------------------------------------------
log_header "Detecting Operating System"

OS="unknown"
case "$(uname -s 2>/dev/null || echo unknown)" in
  Linux*)   OS="linux" ;;
  Darwin*)  OS="mac" ;;
  CYGWIN*|MINGW*|MSYS*) OS="windows" ;;
  *) OS="unknown" ;;
esac

log_info "Detected OS: $OS"
echo ""

# ------------------------------------------------------------
# Docker Desktop Check
# ------------------------------------------------------------
log_header "Checking Docker Desktop"

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
    log_ok "Docker Desktop is running (version: $DOCKER_VERSION)"
  else
    log_error "Docker Desktop installed but NOT running"
    echo "Please start Docker Desktop and rerun this script"
    exit 1
  fi
else
  log_error "Docker Desktop is not installed"
  echo "Download from: https://www.docker.com/products/docker-desktop/"
  exit 1
fi
echo ""

# ------------------------------------------------------------
# Python Detection (simplified)
# ------------------------------------------------------------
log_header "Checking Python"

PYTHON_CMD=""

# Try python3
if command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD="python3"
# Try python (check if it's Python 3)
elif command -v python >/dev/null 2>&1; then
  PYVER=$(python --version 2>&1 | head -1)
  if echo "$PYVER" | grep -q "Python 3"; then
    PYTHON_CMD="python"
  fi
fi

# Windows: try py launcher
if [ -z "$PYTHON_CMD" ] && [ "$OS" = "windows" ]; then
  if command -v py >/dev/null 2>&1; then
    PYTHON_CMD="py -3"
  fi
fi

if [ -z "$PYTHON_CMD" ]; then
  log_error "Python 3 not found"
  echo "Please install Python 3.8 or higher"
  echo "Download from: https://www.python.org/downloads/"
  exit 1
fi

# Get Python version
PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | head -1 | awk '{print $2}')
log_ok "Python found: $PYTHON_VERSION ($PYTHON_CMD)"

# Check pip
if $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
  log_ok "pip is available"
else
  log_warn "pip not found, attempting to install..."
  $PYTHON_CMD -m ensurepip --upgrade 2>/dev/null || true
fi

# Install Python packages (always try, pip will skip if installed)
log_info "Installing Python dependencies (click, rich)..."
$PYTHON_CMD -m pip install --quiet --upgrade click rich 2>/dev/null || \
$PYTHON_CMD -m pip install --quiet --user click rich 2>/dev/null || \
log_warn "Could not install Python packages (may need manual installation)"

log_ok "Python setup complete"
echo ""

# ------------------------------------------------------------
# Kubernetes Tools Check
# ------------------------------------------------------------
log_header "Checking Kubernetes Tools"

check_tool() {
  local tool=$1
  if command -v "$tool" >/dev/null 2>&1; then
    log_ok "$tool is installed"
    return 0
  else
    log_error "$tool is not installed"
    return 1
  fi
}

TOOLS_OK=true
check_tool kubectl || TOOLS_OK=false
check_tool minikube || TOOLS_OK=false
check_tool helm || TOOLS_OK=false

if [ "$TOOLS_OK" = "false" ]; then
  echo ""
  log_error "Some required tools are missing"
  echo ""
  echo "Installation instructions:"
  echo "  kubectl:  https://kubernetes.io/docs/tasks/tools/"
  echo "  minikube: https://minikube.sigs.k8s.io/docs/start/"
  echo "  helm:     https://helm.sh/docs/intro/install/"
  exit 1
fi
echo ""

# ------------------------------------------------------------
# Configure Minikube
# ------------------------------------------------------------
log_header "Configuring Minikube"

log_info "Setting Minikube driver to Docker..."
minikube config set driver docker >/dev/null 2>&1 || true
log_ok "Minikube driver configured"
echo ""

# ------------------------------------------------------------
# Start Minikube
# ------------------------------------------------------------
log_header "Starting Minikube"

if minikube status >/dev/null 2>&1; then
  log_ok "Minikube is already running"
else
  log_info "Starting Minikube (this may take a few minutes)..."
  
  if minikube start \
    --driver=docker \
    --cpus=4 \
    --memory=8192 \
    --disk-size=20g \
    --kubernetes-version=stable \
    >/dev/null 2>&1; then
    log_ok "Minikube started successfully"
  else
    log_error "Failed to start Minikube"
    echo "Try running: minikube delete && minikube start"
    exit 1
  fi
fi

# Verify cluster access
if kubectl cluster-info >/dev/null 2>&1; then
  log_ok "Kubernetes cluster is accessible"
else
  log_error "Cannot connect to Kubernetes cluster"
  exit 1
fi
echo ""

# ------------------------------------------------------------
# Enable Minikube Addons
# ------------------------------------------------------------
log_header "Configuring Minikube Addons"

enable_addon() {
  local addon=$1
  if minikube addons list 2>/dev/null | grep -q "$addon.*enabled"; then
    log_ok "Addon enabled: $addon"
  else
    log_info "Enabling addon: $addon"
    minikube addons enable "$addon" >/dev/null 2>&1 || true
  fi
}

enable_addon "metrics-server"
enable_addon "dashboard"
echo ""

# ------------------------------------------------------------
# Configure Docker Environment
# ------------------------------------------------------------
log_header "Configuring Docker Environment"

log_info "Pointing Docker to Minikube's daemon..."

# Eval the docker-env output
if [ "$OS" = "windows" ]; then
  eval "$(minikube docker-env --shell bash 2>/dev/null || true)"
else
  eval "$(minikube docker-env 2>/dev/null || true)"
fi

if docker info >/dev/null 2>&1; then
  log_ok "Docker configured to use Minikube's daemon"
else
  log_warn "Could not configure Docker (this is OK, will retry during deployment)"
fi
echo ""

# ------------------------------------------------------------
# Create Debug Pod
# ------------------------------------------------------------
log_header "Setting Up Debug Tools"

if kubectl get pod dns-test >/dev/null 2>&1; then
  log_ok "dns-test pod already exists"
else
  log_info "Creating dns-test pod..."
  kubectl run dns-test \
    --image=busybox:1.36 \
    --restart=Never \
    --command -- sh -c "sleep 3600" >/dev/null 2>&1 || true
  log_ok "dns-test pod created"
fi
echo ""

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo "============================================================"
echo "   ✓ Prerequisites Setup Complete"
echo "============================================================"
echo ""
echo "System Status:"
echo "  • Docker Desktop:  Running"
echo "  • Python:          $PYTHON_VERSION"
echo "  • kubectl:         Installed"
echo "  • minikube:        Running"
echo "  • helm:            Installed"
echo ""
echo "============================================================"
echo ""
echo "Next Steps:"
echo "  1. Run: make deploy"
echo "  2. Or:  python3 deploy.py deploy"
echo ""
echo "Useful Commands:"
echo "  • make status      - Check deployment status"
echo "  • make open        - Open UI in browser"
echo "  • kubectl get pods - View all pods"
echo ""