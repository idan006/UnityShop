import os
import subprocess
import sys
import platform
from pathlib import Path

# ============================================================
# Project UUID
# ============================================================
UUID = "e271b052-9200-4502-b491-62f1649c07"

print("============================================================")
print("           UnityExpress – Full Deployment Tool")
print(f"                 PROJECT UUID: {UUID}")
print("============================================================\n")


# ============================================================
# Detect REAL project root (works from any folder)
# ============================================================

def find_project_root(start: Path):
    current = start
    while True:
        if (
            (current / "api-server").is_dir() and
            (current / "charts").is_dir() and
            (current / "monitoring").is_dir() and
            (current / "scripts").is_dir()
        ):
            return current

        parent = current.parent
        if parent == current:
            break
        current = parent

    print("[ERROR] Could not locate UnityExpress project root.")
    print("Run this script from inside the UnityExpress folder.")
    sys.exit(1)


SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = find_project_root(SCRIPT_DIR)

print(f"[*] Project root detected as: {PROJECT_ROOT}\n")

# Paths now work correctly:
MONITORING_VALUES = PROJECT_ROOT / "monitoring" / "prometheus-adapter-values.yaml"
CHART_PATH = PROJECT_ROOT / "charts" / "unityexpress"


# ============================================================
# Utility Functions
# ============================================================

def run(cmd, check=True, capture=False):
    print(f"\n>>> {cmd}")
    if capture:
        return subprocess.check_output(cmd, shell=True, text=True)
    result = subprocess.run(cmd, shell=True)
    if check and result.returncode != 0:
        print(f"[ERROR] Command failed: {cmd}")
        sys.exit(1)
    return result


def header(text):
    print("\n" + "="*60)
    print(text)
    print("="*60 + "\n")


def detect_os():
    system = platform.system().lower()
    if "windows" in system:
        return "windows"
    elif "darwin" in system:
        return "mac"
    return "linux"


OS = detect_os()


# ============================================================
# 1. Validate monitoring file exists
# ============================================================

if not MONITORING_VALUES.exists():
    print(f"[ERROR] Missing monitoring adapter config:\n{MONITORING_VALUES}")
    sys.exit(1)


# ============================================================
# 2. Ensure Minikube is running
# ============================================================

header("Checking Minikube Status")

status = run("minikube status", check=False)
if status.returncode != 0:
    print("[ERROR] Minikube is NOT running.")
    sys.exit(1)
print("[OK] Minikube is active.")


# ============================================================
# 3. Install Monitoring Stack
# ============================================================

header(f"Installing Monitoring Stack (UUID: {UUID})")

run("helm repo add prometheus-community https://prometheus-community.github.io/helm-charts", check=False)
run("helm repo update")

run(
    f"helm upgrade --install monitoring prometheus-community/kube-prometheus-stack "
    f"-n monitoring --create-namespace"
)

run(
    f"helm upgrade --install prometheus-adapter prometheus-community/prometheus-adapter "
    f"-n monitoring -f {MONITORING_VALUES}"
)

print(f"[OK] Monitoring installed. UUID={UUID}")


# ============================================================
# 4. Configure Docker inside Minikube
# ============================================================

header(f"Configuring Docker for Minikube (UUID: {UUID})")

if OS in ("linux", "mac"):
    output = run("minikube docker-env", capture=True)
    for line in output.splitlines():
        if "export" in line:
            key, val = line.replace("export ", "").split("=", 1)
            os.environ[key] = val.strip('"')
elif OS == "windows":
    output = run("minikube docker-env --shell bash", capture=True)
    for line in output.splitlines():
        if "export" in line:
            key, val = line.replace("export ", "").split("=", 1)
            os.environ[key] = val.strip('"')

run("docker info")
print("[OK] Docker linked to Minikube.")


# ============================================================
# 5. Build Docker Images
# ============================================================

header(f"Building UnityExpress Images (UUID: {UUID})")

run(f"docker build -t unityexpress-api:local {PROJECT_ROOT / 'api-server'}")
run(f"docker build -t unityexpress-web:local {PROJECT_ROOT / 'web-server'}")

print(f"[OK] Images built successfully. UUID={UUID}")


# ============================================================
# 6. Deploy UnityExpress Helm Chart
# ============================================================

header(f"Deploying UnityExpress (UUID: {UUID})")

run(
    f"helm upgrade --install unityexpress {CHART_PATH} "
    f"-n unityexpress --create-namespace "
    f"--set projectUuid={UUID}"
)

run("kubectl wait --for=condition=Available deployment/unityexpress-api -n unityexpress --timeout=90s", check=False)
run("kubectl wait --for=condition=Available deployment/unityexpress-web -n unityexpress --timeout=90s", check=False)


# ============================================================
# 7. List resources
# ============================================================

header("UnityExpress Kubernetes Resources")
run("kubectl get pods,svc,hpa -n unityexpress -o wide")


# ============================================================
# 8. Output Web URL
# ============================================================

header("UnityExpress Deployment Complete")

try:
    url = run("minikube service unityexpress-web -n unityexpress --url", capture=True).splitlines()[0]
    print(f"WEB UI: {url}")
except:
    print("[WARN] Could not detect service URL.")

print(f"\nUUID: {UUID}")
print("\n============================================================")
print("              UnityExpress deployed successfully!")
print("============================================================\n")
