#!/usr/bin/env bash
set -e

NAMESPACE="unityexpress"

echo "[*] Port-forwarding unityexpress-api service to localhost:30080"
kubectl port-forward svc/unityexpress-api -n "$NAMESPACE" 30080:80 &
PF_PID=$!
sleep 5

echo "[*] Creating a test purchase"
curl -s -X POST "http://localhost:30080/api/purchases" \
  -H "Content-Type: application/json" \
  -d '{"username":"idan","userid":"user-123","price":99.9,"timestamp":"'$(date -Iseconds)'"}' | jq .

echo "[*] Reading all purchases"
curl -s "http://localhost:30080/api/purchases" | jq .

kill "$PF_PID" || true
