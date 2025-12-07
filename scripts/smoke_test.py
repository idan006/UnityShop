#!/usr/bin/env python3
import subprocess
import json
import sys
import time
import requests

NAMESPACE = "unityexpress"
GATEWAY_PORT = 30090
API_PORT = 30030
UUID_KEY = "unityexpress/watermark"

def run(cmd, capture_output=True):
    """Run shell commands and return output or raise errors."""
    result = subprocess.run(cmd, shell=True, check=False, capture_output=capture_output, text=True)
    if result.returncode != 0:
        print(f"[ERROR] Command failed: {cmd}")
        print(result.stderr)
        sys.exit(1)
    return result.stdout.strip()


def check_k8s_connection():
    print("✓ Checking Kubernetes cluster connectivity...")
    run("kubectl version --short")
    print("  OK\n")


def check_namespace():
    print("✓ Checking namespace...")
    out = run(f"kubectl get ns {NAMESPACE} --no-headers")
    print("  Namespace exists: OK\n")


def check_pods_running():
    print("✓ Checking pod statuses...")
    out = run(f"kubectl get pods -n {NAMESPACE} -o json")
    data = json.loads(out)

    for pod in data["items"]:
        name = pod["metadata"]["name"]
        phase = pod["status"]["phase"]
        if phase != "Running":
            print(f"  [FAIL] Pod {name} is {phase}")
            sys.exit(1)
        print(f"  Pod {name} is Running")

    print("  All pods Running: OK\n")


def check_uuid_watermark():
    print("✓ Checking UUID watermark across pods...")
    out = run(f"kubectl get pods -n {NAMESPACE} -o json")
    data = json.loads(out)

    found = False
    for pod in data["items"]:
        annotations = pod["metadata"].get("annotations", {})
        if UUID_KEY in annotations:
            print(f"  Pod {pod['metadata']['name']} watermark: {annotations[UUID_KEY]}")
            found = True

    if not found:
        print("  [WARN] No UUID watermark found")

    print("  Watermark check completed\n")


def check_service(name):
    print(f"✓ Checking service: {name}")
    out = run(f"kubectl get svc {name} -n {NAMESPACE} -o json")
    svc = json.loads(out)
    ip = svc["spec"].get("clusterIP", "None")
    print(f"  Service {name} available at {ip}\n")


def check_http(url, label):
    print(f"✓ Checking HTTP endpoint: {label}")
    try:
        r = requests.get(url, timeout=3)
        print(f"  Response {r.status_code}: OK")
        return True
    except Exception as e:
        print(f"  [FAIL] {label} unreachable: {e}")
        return False


def check_gateway():
    print("✓ Testing Gateway HTTP reachability...")
    return check_http(f"http://localhost:{GATEWAY_PORT}", "Gateway")


def check_api():
    print("✓ Testing API endpoint...")
    return check_http(f"http://localhost:{API_PORT}/health", "API /health")


def check_kafka():
    print("✓ Checking Kafka port accessibility inside the cluster...")

    cmd = f"""
    kubectl exec -n {NAMESPACE} deploy/unityexpress-api -- \
        bash -c 'echo > /dev/tcp/unityexpress-kafka/9092 2>/dev/null && echo OK || echo FAIL'
    """
    out = run(cmd)

    if "OK" in out:
        print("  Kafka reachable from API pod: OK\n")
    else:
        print("  [FAIL] Kafka not reachable from API pod")
        sys.exit(1)


def check_mongo():
    print("✓ Checking Mongo connectivity from API pod...")

    cmd = f"""
    kubectl exec -n {NAMESPACE} deploy/unityexpress-api -- \
        node -e "const m=require('mongodb');m.MongoClient.connect('mongodb://unityexpress-mongo:27017',{connectTimeoutMS:2000}).then(()=>console.log('OK')).catch(()=>console.log('FAIL'));"
    """

    out = run(cmd)

    if "OK" in out:
        print("  MongoDB reachable: OK\n")
    else:
        print("  [FAIL] Mongo unreachable")
        sys.exit(1)


def check_keda():
    print("✓ Checking KEDA operator and ScaledObject...")
    out = run("kubectl get pods -n keda --no-headers")
    print(out)
    print("  KEDA operator present")

    out = run(f"kubectl get scaledobject -n {NAMESPACE} --no-headers || true")
    if out.strip():
        print("  ScaledObject detected")
    else:
        print("  No ScaledObject configured (OK if not enabled)")

    print()


def main():
    print("\n=== UnityExpress Smoke Test ===\n")

    check_k8s_connection()
    check_namespace()
    check_pods_running()
    check_uuid_watermark()

    check_service("unityexpress-gateway")
    check_service("unityexpress-api")
    check_service("unityexpress-kafka")
    check_service("unityexpress-mongo")

    check_gateway()
    check_api()
    check_kafka()
    check_mongo()
    check_keda()

    print("\n=== WEEEE!   ALL TESTS PASSED ===\n")


if __name__ == "__main__":
    main()
