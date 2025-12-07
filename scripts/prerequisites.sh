#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Colors
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

echo -e "============================================================"
echo -e "        UnityExpress - Cross-Platform Installer"
echo -e "============================================================"

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
# Helper: determine sudo usage on *nix
# ------------------------------------------------------------
SUDO=""
if [ "${OS}" = "linux" ] || [ "${OS}" = "mac" ]; then
  if command -v sudo >/dev/null 2>&1 && [ "${EUID:-1000}" -ne 0 ]; then
    SUDO="sudo"
  else
    SUDO=""
  fi
fi

# ------------------------------------------------------------
# Python detection
# ------------------------------------------------------------
PYTHON_CMD=""

detect_python_cmd() {
  PYTHON_CMD=""
  if [ "$OS" = "windows" ]; then
    # Prefer py -3 on Windows to bypass Store alias
    if command -v py >/dev/null 2>&1; then
      if py -3 -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="py -3"
        return
      fi
    fi
    if command -v python3 >/dev/null 2>&1; then
      if python3 -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="python3"
        return
      fi
    fi
    if command -v python >/dev/null 2>&1; then
      if python -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="python"
        return
      fi
    fi
  else
    if command -v python3 >/dev/null 2>&1; then
      if python3 -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="python3"
        return
      fi
    fi
    if command -v python >/dev/null 2>&1; then
      if python -c "import sys" >/dev/null 2>&1; then
        PYTHON_CMD="python"
        return
      fi
    fi
  fi
}

install_python_windows() {
  log_warn "Python is not available. Attempting installation via Chocolatey..."
  if ! command -v choco >/dev/null 2>&1; then
    log_error "Chocolatey (choco) is not installed. Install it from https://chocolatey.org and rerun."
    exit 1
  fi
  choco install -y python || {
    log_error "Chocolatey installation of Python failed."
    exit 1
  }
  log_ok "Chocolatey finished installing Python. You may need to open a new shell if PATH did not refresh."
}

install_python_unix() {
  log_warn "Python is not available. Attempting installation on ${OS}..."
  if [ "$OS" = "mac" ]; then
    if command -v brew >/dev/null 2>&1; then
      brew install python || {
        log_error "brew install python failed. Install Python manually and rerun."
        exit 1
      }
    else
      log_error "Homebrew not found. Install Python from https://www.python.org/downloads/ and rerun."
      exit 1
    fi
  elif [ "$OS" = "linux" ]; then
    # Try common package managers
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update || true
      $SUDO apt-get install -y python3 python3-pip || {
        log_error "apt-get install python3 failed. Install Python manually and rerun."
        exit 1
      }
    elif command -v yum >/dev/null 2>&1; then
      $SUDO yum install -y python3 || {
        log_error "yum install python3 failed. Install Python manually and rerun."
        exit 1
      }
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y python3 || {
        log_error "dnf install python3 failed. Install Python manually and rerun."
        exit 1
      }
    else
      log_error "Unsupported Linux package manager. Install Python manually and rerun."
      exit 1
    fi
  else
    log_error "Unsupported OS for automatic Python install."
    exit 1
  fi
}

ensure_python() {
  log_info "Checking Python availability..."
  detect_python_cmd
  if [ -z "$PYTHON_CMD" ]; then
    log_warn "No working Python interpreter found in PATH."
    if [ "$OS" = "windows" ]; then
      install_python_windows
    else
      install_python_unix
    fi
    detect_python_cmd
    if [ -z "$PYTHON_CMD" ]; then
      log_error "Python is still not available after installation attempt."
      exit 1
    fi
  fi

  log_ok "Using Python: $PYTHON_CMD"

  # Ensure pip exists (best effort)
  if ! $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
    log_warn "pip not found. Trying to bootstrap pip through ensurepip..."
    $PYTHON_CMD - <<'EOF'
import ensurepip
try:
    ensurepip.bootstrap()
except Exception:
    pass
EOF
  fi

  log_ok "Python and pip are ready."
}

# ------------------------------------------------------------
# Kubernetes toolchain (kubectl, minikube, helm)
# On Windows: try automatic install with Chocolatey.
# On Linux/macOS: show install hints if missing.
# ------------------------------------------------------------
ensure_tool_windows() {
  local bin_name="$1"
  local choco_pkg="$2"

  if command -v "$bin_name" >/dev/null 2>&1; then
    log_ok "$bin_name found: $(command -v "$bin_name")"
    return
  fi

  log_warn "$bin_name not found. Attempting Chocolatey install of package: $choco_pkg"
  if ! command -v choco >/dev/null 2>&1; then
    log_error "choco not found. Install Chocolatey from https://chocolatey.org, then install $choco_pkg manually."
    exit 1
  fi

  choco install -y "$choco_pkg" || {
    log_error "choco install $choco_pkg failed. Install manually and rerun."
    exit 1
  }

  if command -v "$bin_name" >/dev/null 2>&1; then
    log_ok "$bin_name installed: $(command -v "$bin_name")"
  else
    log_error "$bin_name still not found after choco installation. Check PATH and rerun."
    exit 1
  fi
}

ensure_tool_unix() {
  local bin_name="$1"
  local friendly_name="$2"

  if command -v "$bin_name" >/dev/null 2>&1; then
    log_ok "$bin_name found: $(command -v "$bin_name")"
    return
  fi

  log_warn "$bin_name not found. Please install $friendly_name manually."
  if [ "$OS" = "mac" ]; then
    echo "  - Recommended: brew install $friendly_name"
  elif [ "$OS" = "linux" ]; then
    echo "  - Example (Debian/Ubuntu): sudo apt-get install -y $friendly_name"
    echo "  - Or use your distro package manager."
  fi
  exit 1
}

ensure_k8s_toolchain() {
  echo -e "\n============================================================"
  echo -e "   Checking Kubernetes Toolchain"
  echo -e "============================================================"

  if [ "$OS" = "windows" ]; then
    ensure_tool_windows "kubectl" "kubernetes-cli"
    ensure_tool_windows "minikube" "minikube"
    ensure_tool_windows "helm" "kubernetes-helm"
  else
    ensure_tool_unix "kubectl" "kubectl"
    ensure_tool_unix "minikube" "minikube"
    ensure_tool_unix "helm" "helm"
  fi
}

# ------------------------------------------------------------
# Minikube start / repair
# ------------------------------------------------------------
select_minikube_driver() {
  # Prefer VirtualBox when available, fallback to Docker
  if command -v VBoxManage >/dev/null 2>&1; then
    echo "virtualbox"
  elif command -v docker >/dev/null 2>&1; then
    echo "docker"
  else
    echo ""
  fi
}

start_minikube() {
  echo -e "\n============================================================"
  echo -e "   Starting or Repairing Minikube"
  echo -e "============================================================"

  local DRIVER
  DRIVER="$(select_minikube_driver)"

  if [ -z "$DRIVER" ]; then
    log_error "No supported Minikube driver found (VirtualBox or Docker). Install one and rerun."
    exit 1
  fi

  log_info "Selected Minikube driver: $DRIVER"

  if minikube status >/dev/null 2>&1; then
    log_ok "Minikube seems to be running."
  else
    log_warn "Minikube is not running or is misconfigured. Attempting fresh start..."
    minikube delete || true
    minikube start \
      --driver="$DRIVER" \
      --cpus=4 \
      --memory=8192 \
      --addons=metrics-server \
      --addons=dashboard
  fi

  log_info "Validating Minikube status..."
  if ! minikube status >/dev/null 2>&1; then
    log_error "Minikube is not healthy after start attempt."
    exit 1
  fi
  log_ok "Minikube is running."
}

# ------------------------------------------------------------
# Configure Docker to use Minikube internal daemon
# ------------------------------------------------------------
configure_docker_env() {
  echo -e "\n============================================================"
  echo -e "   Configuring Docker to use Minikube Docker daemon"
  echo -e "============================================================"

  case "$OS" in
    linux|mac)
      log_info "Applying docker-env for Linux/macOS..."
      eval "$(minikube docker-env -p minikube)"
      ;;
    windows)
      log_info "Applying docker-env for Windows (Git Bash)..."
      eval "$(minikube docker-env -p minikube --shell bash)"
      ;;
    *)
      log_error "Unknown OS. Cannot configure Docker for Minikube."
      exit 1
      ;;
  esac

  log_info "Checking Docker daemon..."
  if docker info >/dev/null 2>&1; then
    log_ok "Docker is now pointing to the Minikube internal Docker engine."
  else
    log_error "Docker could not connect to Minikube. On Windows, try in PowerShell:"
    echo ""
    echo "  minikube -p minikube docker-env | Invoke-Expression"
    echo ""
    exit 1
  fi
}

# ------------------------------------------------------------
# Keep a dns-test pod for debugging
# ------------------------------------------------------------
ensure_dns_test_pod() {
  echo -e "\n============================================================"
  echo -e "   Ensuring dns-test pod exists"
  echo -e "============================================================"

  if kubectl get pod dns-test >/dev/null 2>&1; then
    log_ok "dns-test pod already exists."
    return
  fi

  log_info "Creating dns-test pod (busybox, sleeping)..."
  kubectl run dns-test \
    --image=busybox:1.36 \
    --restart=Never \
    --command -- sh -c "sleep 3600" || {
      log_warn "Failed to create dns-test pod. You can create it manually if needed."
      return
    }

  log_ok "dns-test pod created. You can exec into it for DNS or network checks."
}

# ------------------------------------------------------------
# Main flow
# ------------------------------------------------------------
ensure_python
ensure_k8s_toolchain
start_minikube
configure_docker_env
ensure_dns_test_pod

echo -e "\n============================================================"
echo -e "   Prerequisites completed successfully"
echo -e "   - Python ready"
echo -e "   - kubectl, minikube, helm available"
echo -e "   - Minikube running"
echo -e "   - Docker points to Minikube"
echo -e "   - dns-test pod available for debugging"
echo -e "============================================================"
echo ""

echo "run " make deploy" if you want to deploy UnityShop now"
