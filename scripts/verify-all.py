#!/usr/bin/env python3
import subprocess, time, sys, webbrowser, platform

# Colors
G="✔"; R="✖"; Y="⚠"; RESET=""

NS = "unityexpress"
MON_NS = "monitoring"

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, text=True)
    except:
        return ""

def ok(msg): print(f"{G} {msg}{RESET}")
def fail(msg): print(f"{R} {msg}{RESET}")
def warn(msg): print(f"{Y} {msg}{RESET}")

def open_browser(url):
    try:
        webbrowser.open(url, new=2)
        ok(f"Opened browser: {url}")
    except Exception:
        warn(f"Could not auto-open browser. Open manually: {url}")

print("\n=== UnityExpress Full Verification Suite ===")


# ============================================================
# 0. ENVIRONMENT CHECK
# ============================================================
env_checks = [
    ("Minikube", "minikube status", "Running"),
    ("kubectl", "kubectl version --client", "Client"),
    ("Kubernetes API", "kubectl get nodes", "Ready"),
    ("Docker", "minikube ssh docker info", "Server"),
    ("Helm", "helm version", "version"),
]

for label, cmd, expect in env_checks:
    out = run(cmd)
    if expect in out:
        ok(label)
    else:
        fail(label)
        sys.exit(1)


# ============================================================
# 1. NAMESPACE
# ============================================================
ns = run(f"kubectl get ns {NS}")
if "Active" in ns:
    ok("Namespace exists")
else:
    fail("Namespace missing")
    sys.exit(1)


# ============================================================
# 2. POD HEALTH
# ============================================================
pods = run(f"kubectl get pods -n {NS} --show-labels")
if "No resources" in pods:
    fail("No pods found")
    sys.exit(1)

ok("Pods detected")

bad_states = ["CrashLoopBackOff","ImagePullBackOff","Error","Evicted","Pending","Terminating"]
issues = [line for line in pods.splitlines() if any(s in line for s in bad_states)]

if issues:
    fail("Unhealthy pod(s) detected")
    for i in issues: print(" ", i)
    sys.exit(1)
else:
    ok("All pods healthy")


# ============================================================
# 3. API HEALTH
# ============================================================
api_pf = subprocess.Popen(
    f"kubectl port-forward svc/unityexpress-api -n {NS} 30080:80",
    shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
time.sleep(2)

api = run("curl -s http://localhost:30080/healthz")

if "ok" in api.lower():
    ok("API health")
else:
    fail("API health")
api_pf.terminate()


# ============================================================
# 4. WEB UI HEALTH
# ============================================================
web_pf = subprocess.Popen(
    f"kubectl port-forward svc/unityexpress-web -n {NS} 31080:80",
    shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
time.sleep(2)

web = run("curl -s http://localhost:31080")

if "<html" in web.lower():
    ok("Web UI")
else:
    fail("Web UI")

web_pf.terminate()


# ============================================================
# 5. MongoDB CHECK
# ============================================================
mongo_pod = run(f"kubectl get pods -n {NS} -o name | grep mongo").strip()
if not mongo_pod:
    fail("Mongo pod missing")
    sys.exit(1)

mongo_status = run(
    f'kubectl exec -n {NS} {mongo_pod} -- mongo --eval "db.runCommand({{ ping: 1 }})"'
)

if '"ok" : 1' in mongo_status:
    ok("MongoDB")
else:
    fail("MongoDB")


# ============================================================
# 6. Kafka CHECK
# ============================================================
kafka_pod = run(f"kubectl get pods -n {NS} -o name | grep kafka").strip()
if not kafka_pod:
    fail("Kafka pod missing")
    sys.exit(1)

run(
    f'kubectl exec -n {NS} {kafka_pod} -- bash -c "echo testmsg | kafka-console-producer.sh --broker-list localhost:9092 --topic test"'
)

kafka_out = run(
    f'kubectl exec -n {NS} {kafka_pod} -- kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic test --from-beginning --timeout-ms 2000'
)

if "testmsg" in kafka_out:
    ok("Kafka")
else:
    fail("Kafka")


# ============================================================
# 7. HPA & CUSTOM METRICS CHECK
# ============================================================
hpa = run(f"kubectl get hpa -n {NS}")
if "No resources" in hpa:
    fail("HPA missing")
else:
    ok("HPA exists")

metrics_api = run('kubectl get --raw "/apis/custom.metrics.k8s.io/v1beta1"')
if "request_latency_seconds" in metrics_api:
    ok("Latency metric registered")
else:
    fail("Latency metric missing")


# ============================================================
# 8. LIGHT AUTOSCALING LOAD
# ============================================================
for _ in range(30):
    run("curl -s http://localhost:30080/healthz >/dev/null")

ok("Autoscaling load sent")


# ============================================================
# 9. MONITORING STACK VERIFICATION
# ============================================================
print("\n=== Monitoring Verification ===")

# Prometheus Operator
op = run(f"kubectl get pods -n {MON_NS} | grep operator")
if "Running" in op:
    ok("Prometheus Operator")
else:
    fail("Prometheus Operator")

# Prometheus
prom = run(f"kubectl get pods -n {MON_NS} | grep prometheus")
if "Running" in prom:
    ok("Prometheus")
else:
    fail("Prometheus")

# Grafana
graf = run(f"kubectl get pods -n {MON_NS} | grep grafana")
if "Running" in graf:
    ok("Grafana")
else:
    fail("Grafana")

# Prometheus Adapter
adapter = run(f"kubectl get pods -n {MON_NS} | grep adapter")
if "Running" in adapter:
    ok("Prometheus Adapter")
else:
    fail("Prometheus Adapter")

# ServiceMonitor
sm = run(f"kubectl get servicemonitor -A")
if "unityexpress" in sm:
    ok("ServiceMonitor registered")
else:
    warn("ServiceMonitor missing")


# ============================================================
# AUTO-OPEN MONITORING UI's
# ============================================================
print("\n=== Opening Monitoring UIs ===")

# Prometheus
prom_pf = subprocess.Popen(
    f"kubectl port-forward svc/monitoring-kube-prometheus-stack-prometheus -n {MON_NS} 9090:9090",
    shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
time.sleep(2)
open_browser("http://localhost:9090")

# Prometheus Targets
open_browser("http://localhost:9090/targets")

# Alertmanager
alert_pf = subprocess.Popen(
    f"kubectl port-forward svc/monitoring-kube-prometheus-stack-alertmanager -n {MON_NS} 9093:9093",
    shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
time.sleep(2)
open_browser("http://localhost:9093")

# Grafana
graf_pf = subprocess.Popen(
    f"kubectl port-forward svc/monitoring-grafana -n {MON_NS} 3000:80",
    shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
time.sleep(2)
open_browser("http://localhost:3000")


# ============================================================
# AUTO-OPEN UNITYEXPRESS WEB UI
# ============================================================
print("\nOpening UnityExpress Web UI...")

ui_pf = subprocess.Popen(
    f"kubectl port-forward svc/unityexpress-web -n {NS} 31080:80",
    shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
)
time.sleep(2)
open_browser("http://localhost:31080")


# ============================================================
# DONE
# ============================================================
print("\n=== Verification Complete ===\n")
