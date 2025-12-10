# UnityExpress Deployment & Testing Guide

This guide walks you through deploying the updated UnityExpress application with the critical improvements (validator, logging, error handling, config validation).

## Prerequisites

Ensure you have installed:
- Docker Desktop (with Kubernetes enabled or Minikube)
- kubectl
- Helm 3+
- minikube (if not using Docker Desktop Kubernetes)

## Step 1: Start Docker & Minikube

### Option A: Using Docker Desktop (Recommended)
```powershell
# Start Docker Desktop
# (Search for Docker Desktop in Windows Start menu and click it)
# Wait ~30 seconds for it to be ready

# Verify Docker is running
docker ps
```

### Option B: Using Minikube
```powershell
# Start Minikube cluster
minikube start --driver=docker

# Verify it's running
minikube status
```

## Step 2: Build Docker Images

```powershell
# Navigate to project root
cd C:\Users\Idan\Desktop\UnityExpress\UnityShop

# Build API server image with new improvements
docker build -t unityexpress-api:local ./api-server

# Build web server image
docker build -t unityexpress-web:local ./web-server

# Verify images were built
docker images | findstr unityexpress
```

**Expected Output:**
```
REPOSITORY              TAG       IMAGE ID       CREATED         SIZE
unityexpress-api        local     abc123...      5 seconds ago    256MB
unityexpress-web        local     def456...      10 seconds ago   150MB
```

## Step 3: Load Images into Minikube (if using Minikube)

```powershell
# Load images so Minikube can access them
minikube image load unityexpress-api:local
minikube image load unityexpress-web:local

# Verify images are loaded
minikube image ls | findstr unityexpress
```

## Step 4: Deploy with Helm

```powershell
# Create namespace
kubectl create namespace unityexpress --dry-run=client -o yaml | kubectl apply -f -

# Deploy/upgrade the Helm chart
helm upgrade --install unityexpress ./charts/unityexpress `
  -n unityexpress `
  --create-namespace `
  --wait `
  --timeout 5m

# Check deployment status
kubectl get pods -n unityexpress
```

**Expected Output:**
```
NAME                                    READY   STATUS    RESTARTS   AGE
unityexpress-api-567d8f5b9c-xxxxx       1/1     Running   0          30s
unityexpress-api-567d8f5b9c-xxxxx       1/1     Running   0          30s
unityexpress-api-567d8f5b9c-xxxxx       1/1     Running   0          30s
unityexpress-mongo-0                    1/1     Running   0          1m
unityexpress-kafka-deployment-xxxxx     1/1     Running   0          45s
unityexpress-web-xxxxx                  1/1     Running   0          50s
unityexpress-nginx-xxxxx                1/1     Running   0          50s
```

## Step 5: Verify Cluster Health

```powershell
# Get all resources
kubectl get all -n unityexpress

# Check services
kubectl get svc -n unityexpress

# Check statefulsets (MongoDB)
kubectl get statefulset -n unityexpress

# View recent events
kubectl get events -n unityexpress --sort-by='.lastTimestamp' | tail -10
```

## Step 6: View Logs to Verify New Features

### Check structured logging output
```powershell
# Get API logs (should see JSON structured logs)
kubectl logs -n unityexpress -l app=unityexpress-api --tail=100 -f

# Look for lines like:
# 2025-12-10 15:45:23 [unityexpress-api] info: Creating purchase {...}
# 2025-12-10 15:45:23 [unityexpress-api] info: Purchase created successfully {...}
```

### Check error handling
```powershell
# Logs should show structured errors
kubectl logs -n unityexpress -l app=unityexpress-api --tail=50 | findstr error
```

### Check config validation
```powershell
# Look for startup logs
kubectl logs -n unityexpress -l app=unityexpress-api --tail=20 | head -5
```

## Step 7: Test the API

### Get the service endpoint
```powershell
# If using Minikube
$minikube_ip = minikube ip
$port = kubectl get svc -n unityexpress unityexpress-nginx -o jsonpath='{.spec.ports[0].nodePort}'
$api_url = "http://$($minikube_ip):$port"
Write-Host "API URL: $api_url"

# If using Docker Desktop Kubernetes
$api_url = "http://localhost"
```

### Test 1: Health Check
```powershell
# Should return { "status": "ok" }
curl -X GET "http://localhost/health" -Headers @{"Content-Type"="application/json"}
```

### Test 2: Create a Purchase (Valid Request)
```powershell
$body = @{
    username = "john_doe"
    userid = "550e8400-e29b-41d4-a716-446655440000"
    price = 99.99
} | ConvertTo-Json

curl -X POST "http://localhost/api/purchases" `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

**Expected Response:**
```json
{
  "purchase": {
    "_id": "abc123...",
    "username": "john_doe",
    "userid": "550e8400-e29b-41d4-a716-446655440000",
    "price": 99.99,
    "timestamp": "2025-12-10T15:45:23.000Z",
    "createdAt": "2025-12-10T15:45:23.000Z",
    "updatedAt": "2025-12-10T15:45:23.000Z"
  }
}
```

### Test 3: Invalid Input (Tests Joi Validator)
```powershell
$body = @{
    username = "ab"  # Too short - validation should fail
    userid = "550e8400-e29b-41d4-a716-446655440000"
    price = 99.99
} | ConvertTo-Json

curl -X POST "http://localhost/api/purchases" `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

**Expected Response (400 Bad Request):**
```json
{
  "error": "Validation failed",
  "details": [
    {
      "field": "username",
      "message": "Username must be at least 3 characters long"
    }
  ]
}
```

### Test 4: Invalid UUID (Tests Joi Validator)
```powershell
$body = @{
    username = "john_doe"
    userid = "not-a-uuid"  # Invalid UUID
    price = 99.99
} | ConvertTo-Json

curl -X POST "http://localhost/api/purchases" `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

**Expected Response (400 Bad Request):**
```json
{
  "error": "Validation failed",
  "details": [
    {
      "field": "userid",
      "message": "User ID must be a valid UUID"
    }
  ]
}
```

### Test 5: Negative Price (Tests Joi Validator)
```powershell
$body = @{
    username = "john_doe"
    userid = "550e8400-e29b-41d4-a716-446655440000"
    price = -50  # Negative price
} | ConvertTo-Json

curl -X POST "http://localhost/api/purchases" `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

**Expected Response (400 Bad Request):**
```json
{
  "error": "Validation failed",
  "details": [
    {
      "field": "price",
      "message": "Price must be a positive number"
    }
  ]
}
```

### Test 6: Retrieve Purchases
```powershell
curl -X GET "http://localhost/api/purchases" `
  -Headers @{"Content-Type"="application/json"}
```

**Expected Response:**
```json
{
  "purchases": [
    {
      "_id": "abc123...",
      "username": "john_doe",
      "userid": "550e8400-e29b-41d4-a716-446655440000",
      "price": 99.99,
      "timestamp": "2025-12-10T15:45:23.000Z"
    }
  ]
}
```

## Step 8: Monitor Logs in Real-Time

```powershell
# Follow all API logs
kubectl logs -n unityexpress -l app=unityexpress-api --tail=50 -f

# Watch for structured JSON output showing:
# - Request creation
# - Validation steps
# - Kafka publish attempts
# - Error handling with errorId
```

## Step 9: Verify Features in Logs

### ✅ Structured Logging
Look for JSON log lines like:
```
2025-12-10 15:45:23 [unityexpress-api] info: Creating purchase {
  "component": "API",
  "username": "john_doe",
  "userid": "550e8400-e29b-41d4-a716-446655440000",
  "price": 99.99
}
```

### ✅ Joi Validator
Logs should show validation errors with detailed messages

### ✅ Error Handler
Failed requests should log with an errorId for tracing:
```
2025-12-10 15:45:24 [unityexpress-api] error: Request failed {
  "errorId": "err-1702225524123-abc123def",
  "statusCode": 400,
  "method": "POST",
  "path": "/api/purchases",
  "message": "Validation failed"
}
```

### ✅ Config Validation
Startup logs should show:
```
2025-12-10 15:45:20 [unityexpress-api] info: Starting UnityExpress API {
  "port": 3000
}
```

## Troubleshooting

### Pods not running?
```powershell
# Check pod status
kubectl describe pod -n unityexpress <pod-name>

# Check logs for errors
kubectl logs -n unityexpress <pod-name> -f
```

### Port not accessible?
```powershell
# Port forward to access service locally
kubectl port-forward -n unityexpress svc/unityexpress-nginx 8080:80
# Now access: http://localhost:8080
```

### Docker image issues?
```powershell
# Rebuild without cache
docker build --no-cache -t unityexpress-api:local ./api-server

# Check image layers
docker history unityexpress-api:local
```

### Reset everything and start fresh?
```powershell
# Delete namespace (removes all resources)
kubectl delete namespace unityexpress

# Rebuild images
docker build -t unityexpress-api:local ./api-server
docker build -t unityexpress-web:local ./web-server

# Redeploy
helm upgrade --install unityexpress ./charts/unityexpress -n unityexpress --create-namespace
```

## Summary of Improvements Deployed

1. **✅ Joi Input Validator Middleware**
   - Validates username, userid (UUID), price
   - Returns detailed error messages
   - Protects against invalid data

2. **✅ Structured JSON Logging (Winston)**
   - All logs are now JSON formatted
   - Includes timestamps, log levels, and context
   - Easy to parse and analyze
   - Search logs for "component", "message", "errorId"

3. **✅ Environment Variable Validation**
   - Fails fast at startup if config is missing
   - Clear error messages
   - Prevents runtime failures

4. **✅ Global Error Handler Middleware**
   - Centralized error handling
   - Each error has unique errorId for tracing
   - Safe error messages (no internal details in production)
   - Full stack traces in logs

---

**Next Steps:**
1. Start Docker Desktop
2. Run the deployment commands above in order
3. Monitor logs: `kubectl logs -n unityexpress -l app=unityexpress-api -f`
4. Test with the curl examples provided
5. Verify JSON structured logs in output
