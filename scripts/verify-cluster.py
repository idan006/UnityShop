import os
import subprocess
import sys
from pathlib import Path
import platform
import time

# Colors
GREEN = "\033[92m"
RED   = "\033[91m"
YELLOW = "\033[93m"
CYAN  = "\033[96m"
RESET = "\033[0m"

NAMESPACE = "unityexpress"
API_SERVICE = "unityexpress-api"
WEB_SERVICE = "unityexpress-web"
HEALTH_PATH = "/healthz"


# -----------------------------------------------------------
# Helper: run shell command
# -----------------------------------------------------------
def run(cmd, capture=False, check=False):
    if capture:
        try:
            return subprocess.check_output(cmd, shell=True, text=True)
        except subprocess.CalledProcessError as e:
            return e.output
    else:
        result = subprocess.run(cmd, shell=True)
        if check and result.returncode != 0:
            print(f"{RED}[ERROR] Command failed:{RESET} {cmd}")
            sys.exit(1)
        return result


# -----------------------------------------------------------
# Header Formatting
# -----------------------------------------------------------
def header(text):
    print("\n" + "=" * 70)
    print(text)
    print("=" * 70 + "\n")


# -----------------------------------------------------------
# Detect OS
# -----------------------------------------------------------
def detect_os():
    s = platform.system().lower()
    if "windows" in s:
        return "windows"
    elif "darwin" in s:
        return "mac"
    return "linux"


OS = detect_os()


# -----------------------------------------------------------
# 1. Check Namespace Exists
# -----------------------------------------------------------
header(f"Checking Namespace '{NAMESPACE}'")

ns_output = run(f"kubectl get ns {NAMESPACE}", capture=True)

if "NotFound" in ns_output or "No resources" in ns_output:
    print(f"{RED}[FAIL] Namespace {NAMESPACE} does not exist.{RESET}")
    sys.exit(1)
else:
    print(f"{GREEN}[OK] Namespace exists.{RESET}")


# -----------------------------------------------------------
# 2. Check Pods Status
# -----------------------------------------------------------
header("Checking Pod Status")

pods_output = run(f"kubectl get pods -n {NAMESPACE} -o wide --show-labels", capture=True)

print(pods_output)

if "No resources found" in pods_output:
    print(f"{RED}[FAIL] No pods found in namespace {NAMESPACE}.{RESET}")
    sys.exit(1)

# Detect problematic pods
bad_states = ["CrashLoopBackOff", "Error", "ImagePullBackOff", "Pending", "Terminating", "Evicted"]
failed = False

for line in pods_output.splitlines():
    if any(state in line for state in bad_states):
        print(f"{RED}[ISSUE] Pod unhealthy:{RESET} {line}")
        failed = True

if not failed:
    print(f"{GREEN}[OK] All pods are running normally.{RESET}")


# -----------------------------------------------------------
# 3. Health Check API Service
# -----------------------------------------------------------
header("API Health Check")

# Port-forward the API service
print(f"{CYAN}[*] Port-forwarding API service on 30080...{RESET}")

api_pf = subprocess.Popen(
    f"kubectl port-forward svc/{API_SERVICE} -n {NAMESPACE} 30080:80",
    shell=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)

time.sleep(5)

api_health = run(f"curl -s http://localhost:30080{HEALTH_PATH}", capture=True)

if "ok" in api_health.lower():
    print(f"{GREEN}[OK] API Health: {api_health}{RESET}")
else:
    print(f"{RED}[FAIL] API health check failed:{RESET} {api_health}")

api_pf.terminate()


# -----------------------------------------------------------
# 4. Health Check Web Service (HTML or JS response)
# -----------------------------------------------------------
header("Web UI Health Check")

print(f"{CYAN}[*] Port-forwarding Web service on 31080...{RESET}")

web_pf = subprocess.Popen(
    f"kubectl port-forward svc/{WEB_SERVICE} -n {NAMESPACE} 31080:80",
    shell=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE
)

time.sleep(5)

web_health = run("curl -s http://localhost:31080", capture=True)

if "<html" in web_health.lower():
    print(f"{GREEN}[OK] Web UI responded successfully.{RESET}")
else:
    print(f"{YELLOW}[WARN] Web UI returned unexpected response:{RESET} {web_health}")

web_pf.terminate()


# -----------------------------------------------------------
# 5. Check HPA Availability
# -----------------------------------------------------------
header("Checking Horizontal Pod Autoscaler")

hpa_out = run(f"kubectl get hpa -n {NAMESPACE}", capture=True)

print(hpa_out)

if "No resources" in hpa_out:
    print(f"{RED}[FAIL] No HPA found.{RESET}")
else:
    print(f"{GREEN}[OK] HPA is present.{RESET}")


# -----------------------------------------------------------
# 6. Final Summary
# -----------------------------------------------------------
header("Cluster Validation Summary")

if failed:
    print(f"{YELLOW}[WARN] Some pods reported issues. Review logs above.{RESET}")

print(f"{GREEN}[OK] Cluster validation complete!{RESET}")
print(f"{CYAN}Use this command to see labels including UUID:{RESET}")
print(f"   kubectl get pods -n {NAMESPACE} --show-labels\n")
