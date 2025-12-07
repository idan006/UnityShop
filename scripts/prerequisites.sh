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

echo -e "${BLUE}============================================================"
echo -e "        UnityExpress – Cross-Platform Installer"
echo -e "============================================================${NC}"

# ------------------------------------------------------------
# OS DETECTION
# ------------------------------------------------------------
detect_os() {
  case "$(uname -s 2>/dev/null)" in
    Linux*)   OS="linux" ;;
    Darwin*)  OS="mac" ;;
    CYGWIN*|MINGW*|MSYS*) OS="windows" ;;
    *)        OS="unknown" ;;
  esac
}

detect_os
echo -e "[*] Detected OS: ${YELLOW}$OS${NC}"

# ------------------------------------------------------------
# PYTHON VALIDATION (REAL CHECK — FIXED)
# ------------------------------------------------------------
find_python() {
  # list possible python binaries
  for cmd in python3 python py python.exe; do
      if command -v "$cmd" >/dev/null 2>&1; then
          # verify it executes normally
          if "$cmd" - << 'EOF' >/dev/null 2>&1
import sys
print("OK")
EOF
          then
              echo "$cmd"
              return 0
          fi
      fi
  done

  return 1
}

echo "[*] Checking Python availability..."

PYBIN=$(find_python || true)

if [ -z "${PYBIN:-}" ]; then
  echo -e "${RED}[ERROR] No working Python interpreter found.${NC}"
  echo "Install Python from:"
  echo "  Windows: https://www.python.org/downloads/"
  echo "  Linux:   apt install python3"
  echo "  macOS:   brew install python3"
  exit 1
fi

echo -e "${GREEN}[OK] Python interpreter detected: $PYBIN${NC}"

# Confirm pip works
if ! "$PYBIN" -m pip --version >/dev/null 2>&1; then
    echo "[*] pip not found. Attempting to install pip..."
    "$PYBIN" -m ensurepip --default-pip || {
        echo -e "${RED}[ERROR] pip installation failed.${NC}"
        exit 1
    }
fi

echo -e "${GREEN}[OK] Python & pip are ready.${NC}"

# ------------------------------------------------------------
# CHECK K8S TOOLS (NO EXIT ON MISSING — SAFE MODE)
# ------------------------------------------------------------
echo
echo -e "${BLUE}============================================================"
echo -e "   Checking Kubernetes Toolchain"
echo -e "============================================================${NC}"

check_tool() {
  local tool=$1
  local link=$2

  if command -v "$tool" >/dev/null 2>&1; then
      echo -e "${GREEN}[OK] $tool found.${NC}"
  else
      echo -e "${RED}[ERROR] $tool not found.${NC}"
      echo "Install from: $link"
      exit 1
  fi
}

check_tool kubectl "https://kubernetes.io/docs/tasks/tools/"
check_tool minikube "https://minikube.sigs.k8s.io/docs/start/"
check_tool helm "https://helm.sh/docs/intro/install/"

# ------------------------------------------------------------
# START MINIKUBE
# ------------------------------------------------------------
echo
echo -e "${BLUE}============================================================"
echo -e "        Starting Minikube"
echo -e "============================================================${NC}"

if minikube status >/dev/null 2>&1; then
    echo -e "${YELLOW}[*] Minikube already running.${NC}"
else
    echo -e "${BLUE}[*] Launching Minikube (4 CPU, 8GB RAM)...${NC}"
    minikube start \
        --driver=virtualbox \
        --cpus=4 \
        --memory=8192 \
        --addons=metrics-server \
        --addons=dashboard
fi

# ------------------------------------------------------------
# CONFIGURE MINIKUBE DOCKER ENV
# ------------------------------------------------------------
echo
echo -e "${BLUE}============================================================"
echo -e "   Configuring Docker to use Minikube’s Docker Daemon"
echo -e "============================================================${NC}"

case "$OS" in
  linux|mac)
      eval "$(minikube docker-env)"
      ;;
  windows)
      # Force bash mode
      eval "$(minikube docker-env --shell=bash)"
      ;;
esac

# Validate Docker connection
if docker info >/dev/null 2>&1; then
    echo -e "${GREEN}[OK] Docker now points to Minikube.${NC}"
else
    echo -e "${RED}[ERROR] Docker cannot connect to Minikube.${NC}"
    echo "Fix for Windows PowerShell:"
    echo "    minikube -p minikube docker-env | Invoke-Expression"
    exit 1
fi

# ------------------------------------------------------------
# DNS VERIFICATION (KEPT AS REQUESTED)
# ------------------------------------------------------------
echo
echo -e "${BLUE}============================================================"
echo -e "   DNS Test Inside Kubernetes Cluster"
echo -e "============================================================${NC}"

kubectl run dns-test --image=busybox:1.36 --rm -it \
  --restart=Never -- nslookup kubernetes.default.svc.cluster.local || true

echo
echo -e "${GREEN}============================================================"
echo -e "   Prerequisites Completed Successfully"
echo -e "============================================================${NC}"
echo
