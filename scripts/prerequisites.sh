#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Colors & Logging helpers
# ------------------------------------------------------------
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[0;36m"
NC="\033[0m"

log_info()    { echo -e "${BLUE}[*]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[✓]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[✗]${NC} $*"; }
log_header()  { echo -e "${CYAN}▶ $*${NC}"; }

trap 'log_error "Script failed on line $LINENO"; exit 1' ERR

echo "============================================================"
echo "      UnityExpress – Cross-Platform Prerequisites Setup"
echo "============================================================"
echo ""

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
echo ""

# ------------------------------------------------------------
# System Requirements Check
# ------------------------------------------------------------
log_header "Checking System Requirements"

check_system_resources() {
  if [ "$OS" = "mac" ] || [ "$OS" = "linux" ]; then
    # Check available memory
    if [ "$OS" = "mac" ]; then
      TOTAL_MEM=$(sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024/1024)}')
    else
      TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
    fi
    
    if [ -n "$TOTAL_MEM" ] && [ "$TOTAL_MEM" -lt 8 ]; then
      log_warn "System has ${TOTAL_MEM}GB RAM. Recommended: 8GB+"
      log_warn "Minikube might run with reduced resources"
    else
      log_ok "System memory: ${TOTAL_MEM}GB"
    fi
    
    # Check available disk space
    if [ "$OS" = "mac" ]; then
      AVAIL_DISK=$(df -g / | awk 'NR==2 {print $4}')
    else
      AVAIL_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    fi
    
    if [ -n "$AVAIL_DISK" ] && [ "$AVAIL_DISK" -lt 20 ]; then
      log_warn "Low disk space: ${AVAIL_DISK}GB available. Recommended: 20GB+"
    else
      log_ok "Available disk space: ${AVAIL_DISK}GB"
    fi
  fi
}

check_system_resources
echo ""

# ------------------------------------------------------------
# Ensure Docker Desktop is installed and running
# ------------------------------------------------------------
log_header "Checking Docker Desktop"

ensure_docker_desktop() {
  if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker Desktop is not installed."
    echo ""

    if [ "$OS" = "windows" ]; then
      echo "Download from: https://www.docker.com/products/docker-desktop/"
      echo "After installation, restart this script."
    elif [ "$OS" = "mac" ]; then
      echo "Install Docker Desktop via:"
      echo "  brew install --cask docker"
      echo "Then open Docker Desktop manually."
    else
      log_error "Linux detected – UnityExpress requires Docker Desktop"
      echo "Download from: https://www.docker.com/products/docker-desktop/"
    fi
    exit 1
  fi

  # Check that daemon is reachable
  if ! docker info >/dev/null 2>&1; then
    log_error "Docker Desktop installed but NOT running."
    echo "Start Docker Desktop manually, then rerun this script."
    exit 1
  fi

  # Check Docker version
  DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")
  log_ok "Docker Desktop is running (version: $DOCKER_VERSION)"
  
  # Check Docker resources
  if docker info 2>/dev/null | grep -q "CPUs:"; then
    DOCKER_CPUS=$(docker info 2>/dev/null | grep "CPUs:" | awk '{print $2}')
    DOCKER_MEM=$(docker info 2>/dev/null | grep "Total Memory:" | awk '{print $3$4}')
    log_info "Docker resources: ${DOCKER_CPUS} CPUs, ${DOCKER_MEM} RAM"
  fi
}

ensure_docker_desktop
echo ""

# ------------------------------------------------------------
# Python detection with version check
# ------------------------------------------------------------
log_header "Checking Python"

detect_python() {
  PYTHON_CMD=""
  if command -v python3 >/dev/null 2>&1; then PYTHON_CMD="python3"; return; fi
  if command -v python >/dev/null 2>&1; then PYTHON_CMD="python"; return; fi
  if command -v py >/dev/null 2>&1; then PYTHON_CMD="py -3"; return; fi
}

ensure_python() {
  detect_python

  if [ -z "${PYTHON_CMD}" ]; then
    log_error "Python not installed. Install Python 3.8+ and rerun."
    exit 1
  fi

  # Check Python version
  PYTHON_VERSION=$($PYTHON_CMD --version 2>&1 | awk '{print $2}')
  PYTHON_MAJOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.major)")
  PYTHON_MINOR=$($PYTHON_CMD -c "import sys; print(sys.version_info.minor)")
  
  if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]); then
    log_error "Python $PYTHON_VERSION detected. Minimum required: 3.8"
    exit 1
  fi
  
  log_ok "Python $PYTHON_VERSION detected"

  # Check for pip
  if ! $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
    log_warn "pip missing. Attempting ensurepip..."
    $PYTHON_CMD -m ensurepip --upgrade || true
  else
    PIP_VERSION=$($PYTHON_CMD -m pip --version | awk '{print $2}')
    log_ok "pip $PIP_VERSION available"
  fi
  
  # Install required Python packages
  log_info "Checking Python dependencies..."
  REQUIRED_PACKAGES=("click" "rich")
  MISSING_PACKAGES=()
  
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! $PYTHON_CMD -c "import $pkg" 2>/dev/null; then
      MISSING_PACKAGES+=("$pkg")
    fi
  done
  
  if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
    log_info "Installing missing packages: ${MISSING_PACKAGES[*]}"
    $PYTHON_CMD -m pip install --quiet "${MISSING_PACKAGES[@]}"
    log_ok "Python dependencies installed"
  else
    log_ok "All Python dependencies available"
  fi
}

ensure_python
echo ""

# ------------------------------------------------------------
# Kubernetes toolchain with version checks
# ------------------------------------------------------------
log_header "Checking Kubernetes Toolchain"

ensure_tool() {
  local tool=$1
  local min_version=${2:-""}
  
  if ! command -v "$tool" >/dev/null 2>&1; then
    log_error "$tool not found"
    echo ""
    case "$tool" in
      kubectl)
        echo "Install kubectl:"
        echo "  Mac:     brew install kubectl"
        echo "  Linux:   snap install kubectl --classic"
        echo "  Windows: choco install kubernetes-cli"
        ;;
      minikube)
        echo "Install minikube:"
        echo "  Mac:     brew install minikube"
        echo "  Linux:   https://minikube.sigs.k8s.io/docs/start/"
        echo "  Windows: choco install minikube"
        ;;
      helm)
        echo "Install helm:"
        echo "  Mac:     brew install helm"
        echo "  Linux:   snap install helm --classic"
        echo "  Windows: choco install kubernetes-helm"
        ;;
    esac
    exit 1
  fi
  
  # Get version
  local version=""
  case "$tool" in
    kubectl)
      version=$(kubectl version --client --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      ;;
    minikube)
      version=$(minikube version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
      ;;
    helm)
      version=$(helm version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
      ;;
  esac
  
  if [ -n "$version" ]; then
    log_ok "$tool found (version: $version)"
  else
    log_ok "$tool found"
  fi
}

ensure_tool kubectl
ensure_tool minikube
ensure_tool helm
echo ""

# ------------------------------------------------------------
# Configure Minikube driver
# ------------------------------------------------------------
log_header "Configuring Minikube"

log_info "Setting Docker as Minikube driver..."
minikube config set driver docker >/dev/null 2>&1 || true
log_ok "Minikube driver set to: docker"
echo ""

# ------------------------------------------------------------
# Start Minikube with optimal settings
# ------------------------------------------------------------
log_header "Starting Minikube"

if minikube status >/dev/null 2>&1; then
  log_ok "Minikube already running"
  
  # Show current config
  CURRENT_CPUS=$(minikube config get cpus 2>/dev/null || echo "4")
  CURRENT_MEM=$(minikube config get memory 2>/dev/null || echo "8192")
  log_info "Current config: ${CURRENT_CPUS} CPUs, ${CURRENT_MEM}MB RAM"
else
  log_info "Starting Minikube with 4 CPUs, 8GB RAM..."
  
  minikube start \
    --driver=docker \
    --cpus=4 \
    --memory=8192 \
    --disk-size=20g \
    --kubernetes-version=stable \
    --addons=metrics-server \
    --addons=dashboard \
    --wait=all
  
  log_ok "Minikube started successfully"
fi

# Verify cluster is accessible
if kubectl cluster-info >/dev/null 2>&1; then
  log_ok "Kubernetes cluster is accessible"
else
  log_error "Cannot connect to Kubernetes cluster"
  exit 1
fi
echo ""

# ------------------------------------------------------------
# Configure Docker to use Minikube's daemon
# ------------------------------------------------------------
log_header "Configuring Docker Environment"

log_info "Pointing Docker to Minikube's daemon..."

if [ "$OS" = "windows" ]; then
  eval "$(minikube docker-env --shell=bash)"
else
  eval "$(minikube docker-env)"
fi

if docker info >/dev/null 2>&1; then
  log_ok "Docker now using Minikube's internal registry"
else
  log_error "Failed to connect Docker to Minikube"
  exit 1
fi
echo ""

# ------------------------------------------------------------
# Verify Minikube addons
# ------------------------------------------------------------
log_header "Verifying Minikube Addons"

REQUIRED_ADDONS=("metrics-server" "dashboard")
for addon in "${REQUIRED_ADDONS[@]}"; do
  if minikube addons list | grep -q "$addon.*enabled"; then
    log_ok "Addon enabled: $addon"
  else
    log_info "Enabling addon: $addon"
    minikube addons enable "$addon" >/dev/null 2>&1
    log_ok "Addon enabled: $addon"
  fi
done
echo ""

# ------------------------------------------------------------
# Create dns-test pod for debugging
# ------------------------------------------------------------
log_header "Setting Up Debug Tools"

log_info "Creating dns-test pod for debugging..."

if kubectl get pod dns-test >/dev/null 2>&1; then
  log_ok "dns-test pod already exists"
else
  kubectl run dns-test \
    --image=busybox:1.36 \
    --restart=Never \
    --command -- sh -c "sleep 3600" >/dev/null 2>&1
  
  # Wait for pod to be ready
  kubectl wait --for=condition=Ready pod/dns-test --timeout=60s >/dev/null 2>&1 || true
  log_ok "dns-test pod created"
fi
echo ""

# ------------------------------------------------------------
# Verify network connectivity
# ------------------------------------------------------------
log_header "Verifying Network Connectivity"

if kubectl exec dns-test -- nslookup kubernetes.default >/dev/null 2>&1; then
  log_ok "Cluster DNS is working"
else
  log_warn "DNS resolution test failed (might be normal on first run)"
fi
echo ""

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo "============================================================"
echo "   ✓ Prerequisites Completed Successfully"
echo "============================================================"
echo ""
echo "System Status:"
echo "  • Docker Desktop:  Running ($DOCKER_VERSION)"
echo "  • Python:          $PYTHON_VERSION"
echo "  • kubectl:         Installed"
echo "  • minikube:        Running (Docker driver)"
echo "  • helm:            Installed"
echo "  • Addons:          metrics-server, dashboard"
echo "  • Debug pod:       dns-test ready"
echo ""
echo "Cluster Info:"
kubectl cluster-info 2>/dev/null | head -2 | sed 's/^/  /'
echo ""
echo "============================================================"
echo ""
echo "Next steps:"
echo "  1. Run: make deploy"
echo "  2. Or:  python3 deploy.py deploy"
echo "  3. Or:  helm install unityexpress ./charts/unityexpress -n unityexpress"
echo ""
echo "Useful commands:"
echo "  • make status         - Check deployment status"
echo "  • make open           - Open UI in browser"
echo "  • make logs           - View application logs"
echo "  • kubectl get pods -A - View all pods"
echo ""