#!/usr/bin/env python3
import os
import platform
import subprocess
import sys
import shutil
import time
import webbrowser

NAMESPACE = "unityexpress"
HELM_CHART = "./charts/unityexpress"
VALUES_FILE = "./charts/unityexpress/values-minikube.yaml"

# ======================================================================================
# Helper Functions
# ======================================================================================

def run(cmd, check=True, shell=True):
    print(f"\n>>> {cmd}")
    result = subprocess.run(cmd, shell=shell)
    if check and result.returncode != 0:
        print(f"❌ ERROR: Command failed: {cmd}")
        sys.exit(1)
    return result.returncode

def exists(binary):
    return shutil.which(binary) is not None

def is_windows():
    return platform.system().lower().startswith("win")

def is_macos():
    return platform.system().lower() == "darwin"

def is_linux():
    return platform.system().lower() == "linux"


# ======================================================================================
# Step 1: Install CLI Tools
# ======================================================================================

def install_kubectl():
    print("\n=== Checking kubectl ===")
    if exists("kubectl"):
        print("✔ kubectl already installed.")
        return

    print("Installing kubectl...")

    if is_linux():
        run("curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl")
        run("chmod +x kubectl")
        run("sudo mv kubectl /usr/local/bin/")
    elif is_macos():
        run("curl -LO https://dl.k8s.io/release/v1.29.0/bin/darwin/amd64/kubectl")
        run("chmod +x kubectl")
        run("sudo mv kubectl /usr/local/bin/")
    elif is_windows():
        print("✔ Downloading kubectl.exe for Windows…")
        run('powershell -Command "Invoke-WebRequest -Uri https://dl.k8s.io/release/v1.29.0/bin/windows/amd64/kubectl.exe -OutFile kubectl.exe"')
        print("Move kubectl.exe to a folder in PATH.")
    else:
        print("❌ Unsupported OS.")
        sys.exit(1)


def install_minikube():
    print("\n=== Checking Minikube ===")
    if exists("minikube"):
        print("✔ Minikube installed.")
        return

    print("Installing Minikube...")

    if is_linux():
        run("curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64")
        run("sudo install minikube-linux-amd64 /usr/local/bin/minikube")
    elif is_macos():
        run("brew install minikube")
    elif is_windows():
        run('powershell -Command "Invoke-WebRequest -Uri https://storage.googleapis.com/minikube/releases/latest/minikube-installer.exe -OutFile minikube-installer.exe"')
        print("Run minikube-installer.exe manually once to register it.")
    else:
        print("❌ Unsupported OS.")
        sys.exit(1)


def install_virtualbox():
    print("\n=== Checking VirtualBox ===")
    if exists("VBoxManage"):
        print("✔ VirtualBox installed.")
        return

    print("❌ VirtualBox is required for --driver=virtualbox")
    print("Install VirtualBox manually:")
    print("- Linux: sudo apt install virtualbox")
    print("- macOS: brew install --cask virtualbox")
    print("- Windows: https://www.virtualbox.org/wiki/Downloads")
    sys.exit(1)


# ======================================================================================
# Step 2: Start Minikube
# ======================================================================================

def start_minikube():
    print("\n=== Starting Minikube with VirtualBox ===")

    run("""
    minikube start \
        --driver=virtualbox \
        --cpus=4 \
        --memory=8192 \
        --addons=metrics-server \
        --addons=dashboard
    """)

    print("\n=== Minikube Status ===")
    run("minikube status")


# ======================================================================================
# Step 3: Install Observability & Autoscaling
# ======================================================================================

def install_prometheus_operator():
    print("\n=== Installing Prometheus Operator ===")
    run("kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -")
    run("kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml")


def install_prometheus_adapter():
    print("\n=== Installing Prometheus Adapter ===")
    run("kubectl apply -f https://github.com/kubernetes-sigs/prometheus-adapter/releases/latest/download/custom-metrics-apiserver-deployment.yaml")


def install_keda():
    print("\n=== Installing KEDA ===")
    run("kubectl create namespace keda --dry-run=client -o yaml | kubectl apply -f -")
    run("""
    kubectl apply -n keda \
      -f https://github.com/kedacore/keda/releases/download/v2.14.0/keda-2.14.0.yaml
    """)


# ======================================================================================
# Step 4: Build Docker Images inside Minikube
# ======================================================================================

def build_local_images():
    print("\n=== Building UnityExpress Docker Images (local) ===")

    if not exists("docker"):
        print("❌ docker is not installed.")
        sys.exit(1)

    run("eval $(minikube docker-env)", check=False)

    if not os.path.exists("./api-server/Dockerfile"):
        print("❌ Missing: ./api-server/Dockerfile")
        sys.exit(1)
    if not os.path.exists("./web-server/Dockerfile"):
        print("❌ Missing: ./web-server/Dockerfile")
        sys.exit(1)

    run("eval $(minikube docker-env) && docker build -t unityexpress-api:local ./api-server")
    run("eval $(minikube docker-env) && docker build -t unityexpress-web:local ./web-server")

    print("✔ Docker images built successfully.")


# ======================================================================================
# Step 5: Prepare Namespace
# ======================================================================================

def create_namespace():
    print(f"\n=== Creating Namespace '{NAMESPACE}' ===")
    run(f"kubectl create namespace {NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -")


# ======================================================================================
# Step 6: Cluster Readiness Checks
# ======================================================================================

def test_cluster_readiness():
    print("\n======================================================")
    print("🔍 Testing Cluster Readiness…")
    print("======================================================")

    print("\n1. Checking nodes")
    run("kubectl get nodes -o wide", check=False)

    print("\n2. Checking DNS resolution")
    run("kubectl run dnspod --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default", check=False)

    print("\n3. Checking metrics server")
    run("kubectl get apiservice | grep metrics", check=False)

    print("\n4. Checking Prometheus Operator")
    run("kubectl get pods -n monitoring", check=False)

    print("\n5. Checking KEDA status")
    run("kubectl get pods -n keda", check=False)

    print("\n6. Checking Minikube Docker images")
    run("eval $(minikube docker-env) && docker images | grep unityexpress", check=False)

    print("\n✔ Readiness checks completed.")
    print("Any failures will typically self-heal over 30–60 seconds.")
    print("======================================================\n")


# ======================================================================================
# Step 7: Deploy Helm Chart
# ======================================================================================

def deploy_helm():
    print("\n=== Deploying UnityExpress Helm Chart ===")

    run(f"""
    helm upgrade --install unityexpress {HELM_CHART} \
      --namespace {NAMESPACE} \
      --create-namespace \
      -f {VALUES_FILE}
    """)

    print("\n✔ UnityExpress deployed successfully!")


# ======================================================================================
# Step 8: Open Web UI
# ======================================================================================

def open_ui():
    print("\n=== Opening UnityExpress Web UI ===")

    result = subprocess.run(
        f"minikube service unityexpress-web -n {NAMESPACE} --url",
        shell=True,
        capture_output=True,
        text=True
    )

    url = result.stdout.strip()

    if url:
        print(f"🌐 Opening: {url}")
        try:
            webbrowser.open(url)
        except:
            print("⚠ Could not open browser automatically. Open manually:")
            print(url)
    else:
        print("❌ Could not determine service URL.")


# ======================================================================================
# MAIN
# ======================================================================================

if __name__ == "__main__":
    print(f"""
===========================================================
 UnityExpress – One-Command Deployment Installer
 Kubernetes + Minikube (VirtualBox)
===========================================================
""")

    install_kubectl()
    install_minikube()
    install_virtualbox()
    start_minikube()

    install_prometheus_operator()
    install_prometheus_adapter()
    install_keda()

    create_namespace()
    build_local_images()
    test_cluster_readiness()

    deploy_helm()
    open_ui()

    print("""
===========================================================
🎉 Deployment Complete – UnityExpress is now running!

Components:
 - MongoDB Pod
 - Kafka Pod
 - API Server Pod (autoscaling via CPU + latency + Kafka lag)
 - Web Server Pod
 - Prometheus Operator + Adapter
 - KEDA

Open the UI or run:
   minikube service unityexpress-web -n unityexpress

Enjoy!
===========================================================
""")
