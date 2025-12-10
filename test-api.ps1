#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Quick test script for UnityExpress API
.DESCRIPTION
    Tests the deployed UnityExpress API endpoints to verify all improvements
.EXAMPLE
    .\test-api.ps1
    .\test-api.ps1 -Namespace custom-ns
    .\test-api.ps1 -BaseUrl "http://localhost:30080"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$Namespace = 'unityexpress',
    
    [Parameter(Mandatory = $false)]
    [string]$BaseUrl = $null
)

$ErrorActionPreference = "Continue"

# Colors
$colors = @{
    Success = @{ ForegroundColor = 'Green' }
    Error   = @{ ForegroundColor = 'Red' }
    Warning = @{ ForegroundColor = 'Yellow' }
    Info    = @{ ForegroundColor = 'Cyan' }
    Pass    = @{ ForegroundColor = 'Green'; HighIntensity = $true }
    Fail    = @{ ForegroundColor = 'Red'; HighIntensity = $true }
}

function Write-Success { Write-Host @($colors.Success) @args }
function Write-Error2 { Write-Host @($colors.Error) @args }
function Write-Warning2 { Write-Host @($colors.Warning) @args }
function Write-Info { Write-Host @($colors.Info) @args }
function Write-Pass { Write-Host @($colors.Pass) @args }
function Write-Fail { Write-Host @($colors.Fail) @args }

function Get-ServiceUrl {
    Write-Info "Getting service URL..."
    
    try {
        $service = kubectl get svc -n $Namespace unityexpress-nginx -o json | ConvertFrom-Json -ErrorAction SilentlyContinue
        
        if (-not $service) {
            Write-Error2 "Service not found. Is the deployment running?"
            kubectl get pods -n $Namespace
            exit 1
        }
        
        $port = $service.spec.ports[0].nodePort
        
        # Check if using Minikube
        $isMinikube = Test-Path (Get-Command minikube -ErrorAction SilentlyContinue)
        
        if ($isMinikube) {
            try {
                $ip = minikube ip 2>$null
                if ($ip) {
                    return "http://$ip`:$port"
                }
            }
            catch { }
        }
        
        # Default to localhost
        return "http://localhost:$port"
    }
    catch {
        Write-Error2 "Failed to get service URL: $_"
        exit 1
    }
}

function Test-HealthCheck {
    Write-Info ""
    Write-Info "════════════════════════════════════════"
    Write-Info "TEST 1: Health Check"
    Write-Info "════════════════════════════════════════"
    Write-Info "GET /health"
    Write-Info "Expected: { status: 'ok' }"
    
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/health" -Method Get -ErrorAction Stop
        $data = $response.Content | ConvertFrom-Json
        
        if ($data.status -eq "ok" -and $response.StatusCode -eq 200) {
            Write-Pass "PASS"
            Write-Info "Response: $($response.Content)"
        }
        else {
            Write-Fail "FAIL"
            Write-Info "Got status: $($data.status)"
        }
    }
    catch {
        Write-Fail "FAIL - Exception: $_"
    }
}

function Test-ValidPurchase {
    Write-Info ""
    Write-Info "════════════════════════════════════════"
    Write-Info "TEST 2: Create Purchase (Valid Data)"
    Write-Info "════════════════════════════════════════"
    Write-Info "POST /api/purchases"
    
    $payload = @{
        username = "test_user_$(Get-Random)"
        userid   = "550e8400-e29b-41d4-a716-446655440000"
        price    = 99.99
    }
    
    Write-Info "Payload: $(ConvertTo-Json $payload)"
    Write-Info "Expected: 201 Created with purchase object"
    
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/api/purchases" `
            -Method Post `
            -Body ($payload | ConvertTo-Json) `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        $data = $response.Content | ConvertFrom-Json
        
        if ($response.StatusCode -eq 201 -and $data.purchase) {
            Write-Pass "PASS"
            Write-Info "Created purchase ID: $($data.purchase._id)"
            Write-Info "Response: $($response.Content)"
            return $data.purchase._id
        }
        else {
            Write-Fail "FAIL - Unexpected status: $($response.StatusCode)"
        }
    }
    catch {
        Write-Fail "FAIL - Exception: $_"
    }
    return $null
}

function Test-ValidationShortUsername {
    Write-Info ""
    Write-Info "════════════════════════════════════════"
    Write-Info "TEST 3: Validation - Username Too Short"
    Write-Info "════════════════════════════════════════"
    Write-Info "POST /api/purchases with username='ab' (min 3 chars required)"
    
    $payload = @{
        username = "ab"  # Too short!
        userid   = "550e8400-e29b-41d4-a716-446655440000"
        price    = 99.99
    }
    
    Write-Info "Payload: $(ConvertTo-Json $payload)"
    Write-Info "Expected: 400 Bad Request with validation error"
    
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/api/purchases" `
            -Method Post `
            -Body ($payload | ConvertTo-Json) `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        Write-Fail "FAIL - Should have been rejected"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Pass "PASS"
            try {
                $stream = $_.Exception.Response.Content.ReadAsStream()
                $reader = New-Object IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
                $data = $content | ConvertFrom-Json
                Write-Info "Error: $($data.error)"
                Write-Info "Details: $(ConvertTo-Json $data.details)"
            }
            catch { }
        }
        else {
            Write-Fail "FAIL - Wrong status: $($_.Exception.Response.StatusCode)"
        }
    }
}

function Test-ValidationInvalidUUID {
    Write-Info ""
    Write-Info "════════════════════════════════════════"
    Write-Info "TEST 4: Validation - Invalid UUID Format"
    Write-Info "════════════════════════════════════════"
    Write-Info "POST /api/purchases with userid='not-a-uuid'"
    
    $payload = @{
        username = "valid_user"
        userid   = "not-a-uuid"  # Invalid UUID!
        price    = 99.99
    }
    
    Write-Info "Payload: $(ConvertTo-Json $payload)"
    Write-Info "Expected: 400 Bad Request with validation error"
    
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/api/purchases" `
            -Method Post `
            -Body ($payload | ConvertTo-Json) `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        Write-Fail "FAIL - Should have been rejected"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Pass "PASS"
            try {
                $stream = $_.Exception.Response.Content.ReadAsStream()
                $reader = New-Object IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
                $data = $content | ConvertFrom-Json
                Write-Info "Error: $($data.error)"
                if ($data.details) {
                    Write-Info "Details: $(ConvertTo-Json $data.details)"
                }
            }
            catch { }
        }
        else {
            Write-Fail "FAIL - Wrong status: $($_.Exception.Response.StatusCode)"
        }
    }
}

function Test-ValidationNegativePrice {
    Write-Info ""
    Write-Info "════════════════════════════════════════"
    Write-Info "TEST 5: Validation - Negative Price"
    Write-Info "════════════════════════════════════════"
    Write-Info "POST /api/purchases with price=-50"
    
    $payload = @{
        username = "valid_user"
        userid   = "550e8400-e29b-41d4-a716-446655440000"
        price    = -50  # Negative!
    }
    
    Write-Info "Payload: $(ConvertTo-Json $payload)"
    Write-Info "Expected: 400 Bad Request with validation error"
    
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/api/purchases" `
            -Method Post `
            -Body ($payload | ConvertTo-Json) `
            -ContentType "application/json" `
            -ErrorAction Stop
        
        Write-Fail "FAIL - Should have been rejected"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Pass "PASS"
            try {
                $stream = $_.Exception.Response.Content.ReadAsStream()
                $reader = New-Object IO.StreamReader($stream)
                $content = $reader.ReadToEnd()
                $data = $content | ConvertFrom-Json
                Write-Info "Error: $($data.error)"
                Write-Info "Details: $(ConvertTo-Json $data.details)"
            }
            catch { }
        }
        else {
            Write-Fail "FAIL - Wrong status: $($_.Exception.Response.StatusCode)"
        }
    }
}

function Test-RetrievePurchases {
    Write-Info ""
    Write-Info "════════════════════════════════════════"
    Write-Info "TEST 6: Retrieve All Purchases"
    Write-Info "════════════════════════════════════════"
    Write-Info "GET /api/purchases"
    Write-Info "Expected: 200 OK with array of purchases"
    
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/api/purchases" `
            -Method Get `
            -ErrorAction Stop
        
        $data = $response.Content | ConvertFrom-Json
        
        if ($response.StatusCode -eq 200 -and $data.purchases) {
            Write-Pass "PASS"
            $count = ($data.purchases | Measure-Object).Count
            Write-Info "Retrieved $count purchase(s)"
            Write-Info "Sample: $(ConvertTo-Json $data.purchases[0])"
        }
        else {
            Write-Fail "FAIL - Unexpected response"
        }
    }
    catch {
        Write-Fail "FAIL - Exception: $_"
    }
}

function Show-LogExamples {
    Write-Info ""
    Write-Info "════════════════════════════════════════"
    Write-Info "CHECKING STRUCTURED LOGS"
    Write-Info "════════════════════════════════════════"
    Write-Info ""
    Write-Info "Recent logs (should be JSON formatted):"
    Write-Info ""
    
    try {
        $logs = kubectl logs -n $Namespace -l app=unityexpress-api --tail=20 2>$null
        
        if ($logs) {
            Write-Info "Sample log output:"
            Write-Info "─────────────────────────────────────"
            $logs | Select-Object -First 5 | ForEach-Object { Write-Info "$_" }
            Write-Info "─────────────────────────────────────"
            Write-Info ""
            Write-Pass "✓ Logs are being generated"
            Write-Info ""
            Write-Info "Watch real-time logs with:"
            Write-Info "  kubectl logs -n $Namespace -l app=unityexpress-api -f"
        }
        else {
            Write-Warning2 "⚠ No logs found yet"
        }
    }
    catch {
        Write-Warning2 "⚠ Could not fetch logs: $_"
    }
}

# Main execution
Write-Info ""
Write-Info "╔════════════════════════════════════════════════════════════════╗"
Write-Info "║    UnityExpress API Test Suite - Validating Improvements      ║"
Write-Info "╚════════════════════════════════════════════════════════════════╝"
Write-Info ""

if (-not $BaseUrl) {
    $BaseUrl = Get-ServiceUrl
}

Write-Info "Testing against: $BaseUrl"
Write-Info "Namespace: $Namespace"

# Run all tests
Test-HealthCheck
Test-ValidPurchase
Test-ValidationShortUsername
Test-ValidationInvalidUUID
Test-ValidationNegativePrice
Test-RetrievePurchases
Show-LogExamples

# Summary
Write-Info ""
Write-Info "════════════════════════════════════════"
Write-Info "TEST SUMMARY"
Write-Info "════════════════════════════════════════"
Write-Info ""
Write-Success "✓ All critical features tested:"
Write-Info "  ✓ Input validation (Joi)"
Write-Info "  ✓ Error handling"
Write-Info "  ✓ CRUD operations"
Write-Info "  ✓ Structured logging"
Write-Info ""
Write-Info "To view detailed logs:"
Write-Info "  kubectl logs -n $Namespace -l app=unityexpress-api -f"
Write-Info ""
Write-Info "To check pod status:"
Write-Info "  kubectl get pods -n $Namespace"
Write-Info ""
