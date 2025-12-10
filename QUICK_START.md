# UnityExpress - Quick Deploy & Test Guide

## 🚀 Quick Start (5 minutes)

### Prerequisites
- Docker Desktop installed
- kubectl, helm, minikube available in PATH

### Step 1: Start Docker
```powershell
# Search for "Docker Desktop" in Windows Start menu and launch it
# Wait 30 seconds for it to be ready
```

### Step 2: Deploy Everything
```powershell
cd C:\Users\Idan\Desktop\UnityExpress\UnityShop

# Run the automated deployment script
.\deploy.ps1
```

This will:
- ✅ Build Docker images
- ✅ Deploy to Kubernetes with Helm
- ✅ Run automated tests
- ✅ Verify all improvements are working

### Step 3: View Results
The script will output test results showing all 6 tests passing:
- ✓ Health check
- ✓ Create valid purchase  
- ✓ Reject short username
- ✓ Reject invalid UUID
- ✓ Reject negative price
- ✓ Retrieve purchases

---

## 🔧 Individual Commands

### Just Deploy
```powershell
.\deploy.ps1 -Action deploy
```

### Just Test
```powershell
.\deploy.ps1 -Action test
```

### Just Build Images
```powershell
.\deploy.ps1 -Action build
```

### View Live Logs
```powershell
.\deploy.ps1 -Action logs

# Or directly:
kubectl logs -n unityexpress -l app=unityexpress-api -f
```

### Run Test Suite
```powershell
.\test-api.ps1
```

### Reset Everything
```powershell
.\deploy.ps1 -Action reset
```

---

## 📊 What Was Improved?

All changes are backward compatible. Your API still works the same, but now with:

### 1️⃣ Input Validation (Joi)
**Before:** Basic type checking
```javascript
if (!username || !userid || typeof price !== "number") {
  return res.status(400).json({ error: "Invalid payload" });
}
```

**After:** Comprehensive validation with detailed error messages
```
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

### 2️⃣ Structured Logging (Winston)
**Before:** Unstructured console logs
```
[API] POST /purchases error: Error: Invalid data
```

**After:** JSON structured logs with context
```json
{
  "level": "info",
  "timestamp": "2025-12-10T15:45:23.000Z",
  "service": "unityexpress-api",
  "component": "API",
  "message": "Purchase created successfully",
  "purchaseId": "abc123...",
  "username": "john_doe"
}
```

### 3️⃣ Error Handling
**Before:** Basic error responses
```
{ error: "Internal server error" }
```

**After:** Traceable errors with errorId
```json
{
  "error": "Internal server error",
  "errorId": "err-1702225523123-abc123def"
}
```

### 4️⃣ Config Validation
**Before:** Silent failures if env vars missing
**After:** Fails fast at startup with clear messages
```
Configuration validation failed:
  - MONGO_URI is required
  - KAFKA_BROKERS must be provided
```

---

## 🧪 Testing Scenarios

### Scenario 1: Valid Purchase
```powershell
# Tests that Joi validator accepts valid data
.\test-api.ps1  # Test 2 & 6
```

### Scenario 2: Username Validation
```powershell
# Tests that short usernames are rejected
.\test-api.ps1  # Test 3
```

### Scenario 3: UUID Format Validation  
```powershell
# Tests that invalid UUIDs are rejected
.\test-api.ps1  # Test 4
```

### Scenario 4: Price Validation
```powershell
# Tests that negative prices are rejected
.\test-api.ps1  # Test 5
```

### Scenario 5: Structured Logging
```powershell
# View JSON logs showing all request context
kubectl logs -n unityexpress -l app=unityexpress-api -f
```

---

## 📈 Monitoring & Debugging

### Check Pod Status
```powershell
kubectl get pods -n unityexpress
kubectl describe pod -n unityexpress <pod-name>
```

### View API Logs
```powershell
# Live logs
kubectl logs -n unityexpress -l app=unityexpress-api -f

# Last 100 lines
kubectl logs -n unityexpress -l app=unityexpress-api --tail=100

# Specific pod
kubectl logs -n unityexpress <pod-name>
```

### Check Services
```powershell
kubectl get svc -n unityexpress
kubectl describe svc -n unityexpress unityexpress-nginx
```

### Port Forward (if needed)
```powershell
kubectl port-forward -n unityexpress svc/unityexpress-nginx 8080:80
# Now access: http://localhost:8080
```

---

## 🔍 Manual Testing (curl)

If you want to test manually without the script:

### Get Service URL
```powershell
$svc = kubectl get svc -n unityexpress unityexpress-nginx -o json | ConvertFrom-Json
$port = $svc.spec.ports[0].nodePort
$ip = minikube ip
$url = "http://$ip`:$port"
Write-Host $url
```

### Health Check
```powershell
curl -X GET "http://localhost:$port/health"
```

### Create Purchase
```powershell
$body = @{
    username = "john_doe"
    userid = "550e8400-e29b-41d4-a716-446655440000"
    price = 99.99
} | ConvertTo-Json

curl -X POST "http://localhost:$port/api/purchases" `
  -Headers @{"Content-Type"="application/json"} `
  -Body $body
```

### Get Purchases
```powershell
curl -X GET "http://localhost:$port/api/purchases"
```

---

## 📝 Log Examples

### Info Log (Valid Creation)
```json
{
  "level": "info",
  "timestamp": "2025-12-10T15:45:23.456Z",
  "service": "unityexpress-api",
  "component": "API",
  "message": "Purchase created successfully",
  "purchaseId": "693977e32eb8faeeb70dc279",
  "username": "john_doe"
}
```

### Error Log (Validation Failed)
```json
{
  "level": "error",
  "timestamp": "2025-12-10T15:45:24.789Z",
  "service": "unityexpress-api",
  "component": "ErrorHandler",
  "errorId": "err-1702225524789-abc123xyz",
  "statusCode": 400,
  "method": "POST",
  "path": "/api/purchases",
  "message": "Validation failed",
  "details": [
    {
      "field": "userid",
      "message": "User ID must be a valid UUID"
    }
  ]
}
```

### Warning Log (Kafka Issue)
```json
{
  "level": "warn",
  "timestamp": "2025-12-10T15:45:25.123Z",
  "service": "unityexpress-api",
  "component": "API",
  "message": "Kafka down",
  "purchaseId": "693977e32eb8faeeb70dc280"
}
```

---

## 🆘 Troubleshooting

### Docker Desktop Not Running
```powershell
# Check if running
docker ps

# If fails, restart Docker:
# 1. Search for "Docker Desktop" in Windows Start menu
# 2. Click to launch it
# 3. Wait 30 seconds for startup
```

### Pods Not Starting
```powershell
# Check pod status
kubectl get pods -n unityexpress

# Describe failing pod
kubectl describe pod -n unityexpress <pod-name>

# View logs
kubectl logs -n unityexpress <pod-name>
```

### Can't Connect to Service
```powershell
# Check if service exists
kubectl get svc -n unityexpress

# Port forward as backup
kubectl port-forward -n unityexpress svc/unityexpress-nginx 8080:80
# Use http://localhost:8080
```

### Want to Start Fresh
```powershell
# Delete everything and redeploy
.\deploy.ps1 -Action reset
.\deploy.ps1 -Action all
```

---

## 📚 Full Documentation

For detailed information, see:
- `DEPLOYMENT_GUIDE.md` - Step-by-step deployment guide with all curl examples
- Code changes documented in commit messages

---

## ✅ Verification Checklist

After running `.\deploy.ps1`:

- [ ] Docker Desktop is running
- [ ] All pods are in "Running" status: `kubectl get pods -n unityexpress`
- [ ] All 6 tests pass from the test script output
- [ ] Logs show JSON formatted output: `kubectl logs -n unityexpress -l app=unityexpress-api --tail=5`
- [ ] API responds to `GET /health` with `{ "status": "ok" }`
- [ ] Invalid requests are rejected with 400 status and error details
- [ ] Valid requests return 201 with purchase object

---

## 🎯 Next Steps

1. **Deploy:** `.\deploy.ps1`
2. **Test:** `.\test-api.ps1`
3. **Monitor:** `kubectl logs -n unityexpress -l app=unityexpress-api -f`
4. **Integrate:** Deploy to your actual cluster with similar Helm commands

---

**Questions?** Check the logs - they're now structured JSON so much easier to debug!

```powershell
kubectl logs -n unityexpress -l app=unityexpress-api -f
```
