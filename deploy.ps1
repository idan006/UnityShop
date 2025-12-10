#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Automated deployment script for UnityExpress with validation and testing
.DESCRIPTION
    Deploys the updated UnityExpress application and runs comprehensive tests
.PARAMETER Action
    The action to perform: build, deploy, test, logs, or all
#>

param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('build', 'deploy', 'test', 'logs', 'reset', 'all')]
    [string]$Action = 'all',
    
    [Parameter(Mandatory = $false)]
    [string]$Namespace = 'unityexpress'
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Colors for output
$colors = @{
    Success = @{ ForegroundColor = 'Green' }
    Error   = @{ ForegroundColor = 'Red' }
    Warning = @{ ForegroundColor = 'Yellow' }
    Info    = @{ ForegroundColor = 'Cyan' }
}

function Write-Success { Write-Host @($colors.Success) @args }
function Write-Error2 { Write-Host @($colors.Error) @args }
function Write-Warning2 { Write-Host @($colors.Warning) @args }
function Write-Info { Write-Host @($colors.Info) @args }

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    $missing = @()
    
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        $missing += "docker"
    }
    
    if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
        $missing += "kubectl"
    }
    
    if (-not (Get-Command helm -ErrorAction SilentlyContinue)) {
        $missing += "helm"
    }
    
    if ($missing) {
        Write-Error2 "Missing required tools: $($missing -join ', ')"
        Write-Info "Please install them before continuing"
        exit 1
    }
    
    Write-Success "✓ All prerequisites found"
}

function Test-DockerRunning {
    Write-Info "Checking if Docker is running..."
    
    try {
        docker ps | Out-Null
        Write-Success "✓ Docker is running"
        return $true
    }
    catch {
        Write-Error2 "✗ Docker is not running. Please start Docker Desktop"
        Write-Info "Starting Docker Desktop in 5 seconds..."
        Start-Sleep -Seconds 5
        
        # Try to start Docker Desktop
        $dockerPath = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
        if (Test-Path $dockerPath) {
            & $dockerPath
            Write-Info "Waiting for Docker to start (30 seconds)..."
            Start-Sleep -Seconds 30
            return (Test-DockerRunning)
        }
        else {
            Write-Error2 "Could not find Docker Desktop at $dockerPath"
            exit 1
        }
    }
}

function Invoke-Build {
    Write-Info "================================"
    Write-Info "STEP 1: Building Docker Images"
    Write-Info "================================"
    
    $projectRoot = Get-Location
    Write-Info "Building API server image..."
    
    docker build -t unityexpress-api:local ./api-server
    if ($LASTEXITCODE -ne 0) {
        Write-Error2 "Failed to build API image"
        exit 1
    }
    Write-Success "✓ API image built"
    
    Write-Info "Building web server image..."
    docker build -t unityexpress-web:local ./web-server
    if ($LASTEXITCODE -ne 0) {
        Write-Error2 "Failed to build web image"
        exit 1
    }
    Write-Success "✓ Web image built"
    
    Write-Info "Verifying images..."
    $images = docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | Select-String unityexpress
    Write-Success "✓ Built images:"
    $images | ForEach-Object { Write-Host "  $_" }
}

function Invoke-Deploy {
    Write-Info "================================"
    Write-Info "STEP 2: Deploying to Kubernetes"
    Write-Info "================================"
    
    # Check if using Minikube
    $usingMinikube = Test-Path (Get-Command minikube -ErrorAction SilentlyContinue)
    
    if ($usingMinikube) {
        Write-Info "Loading images into Minikube..."
        minikube image load unityexpress-api:local
        minikube image load unityexpress-web:local
        Write-Success "✓ Images loaded into Minikube"
    }
    
    Write-Info "Creating namespace..."
    kubectl create namespace $Namespace --dry-run=client -o yaml | kubectl apply -f -
    Write-Success "✓ Namespace ready"
    
    Write-Info "Deploying with Helm..."
    helm upgrade --install unityexpress ./charts/unityexpress `
        -n $Namespace `
        --create-namespace `
        --wait `
        --timeout 5m
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error2 "Helm deployment failed"
        exit 1
    }
    Write-Success "✓ Helm deployment complete"
    
    Write-Info "Waiting for pods to be ready (60 seconds)..."
    $retries = 0
    $maxRetries = 12
    
    while ($retries -lt $maxRetries) {
        $ready = kubectl get pods -n $Namespace --no-headers | 
                 Where-Object { $_ -match '1/1\s+Running' } | 
                 Measure-Object | 
                 Select-Object -ExpandProperty Count
        
        $total = kubectl get pods -n $Namespace --no-headers | 
                 Measure-Object | 
                 Select-Object -ExpandProperty Count
        
        Write-Info "Pods ready: $ready/$total"
        
        if ($ready -eq $total -and $total -gt 0) {
            Write-Success "✓ All pods are running"
            break
        }
        
        $retries++
        if ($retries -lt $maxRetries) {
            Start-Sleep -Seconds 5
        }
    }
    
    if ($retries -eq $maxRetries) {
        Write-Warning2 "⚠ Timeout waiting for pods. Checking status..."
        kubectl get pods -n $Namespace
    }
}

function Invoke-Test {
    Write-Info "================================"
    Write-Info "STEP 3: Testing the Deployment"
    Write-Info "================================"
    
    # Get the service endpoint
    Write-Info "Getting service endpoint..."
    
    $service = kubectl get svc -n $Namespace unityexpress-nginx -o json | ConvertFrom-Json -ErrorAction SilentlyContinue
    
    if (-not $service) {
        Write-Error2 "Could not find nginx service"
        Write-Info "Available services:"
        kubectl get svc -n $Namespace
        exit 1
    }
    
    $port = $service.spec.ports[0].nodePort
    
    # Determine URL based on platform
    $isMinikube = Test-Path (Get-Command minikube -ErrorAction SilentlyContinue)
    if ($isMinikube) {
        $ip = minikube ip
        $url = "http://$ip`:$port"
    }
    else {
        $url = "http://localhost:$port"
    }
    
    Write-Info "Testing endpoint: $url"
    Write-Success "✓ Service URL: $url"
    
    # Test 1: Health check
    Write-Info ""
    Write-Info "Test 1: Health Check"
    try {
        $response = Invoke-WebRequest -Uri "$url/health" -Method Get -ErrorAction Stop
        $data = $response.Content | ConvertFrom-Json
        if ($data.status -eq "ok") {
            Write-Success "✓ Health check passed"
        }
        else {
            Write-Error2 "✗ Health check failed: $($data.status)"
        }
    }
    catch {
        Write-Error2 "✗ Health check error: $_"
    }
    
    # Test 2: Create purchase with valid data
    Write-Info ""
    Write-Info "Test 2: Create Purchase (Valid UUID)"
    $body = @{
        username = "test_user"
        userid   = "550e8400-e29b-41d4-a716-446655440000"
        price    = 99.99
    } | ConvertTo-Json
    
    try {
        $response = Invoke-WebRequest -Uri "$url/api/purchases" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        $data = $response.Content | ConvertFrom-Json
        if ($data.purchase) {
            Write-Success "✓ Purchase created: $($data.purchase._id)"
        }
        else {
            Write-Error2 "✗ No purchase in response"
        }
    }
    catch {
        Write-Error2 "✗ Create purchase error: $_"
    }
    
    # Test 3: Validation - short username
    Write-Info ""
    Write-Info "Test 3: Validation - Username Too Short"
    $body = @{
        username = "ab"
        userid   = "550e8400-e29b-41d4-a716-446655440000"
        price    = 99.99
    } | ConvertTo-Json
    
    try {
        $response = Invoke-WebRequest -Uri "$url/api/purchases" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Error2 "✗ Should have failed validation"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            $data = $_.Exception.Response.Content.ReadAsStream() | { param($s) New-Object IO.StreamReader($s) }.Invoke($_) | Get-Content | ConvertFrom-Json
            if ($data.error -eq "Validation failed") {
                Write-Success "✓ Validation correctly rejected short username"
            }
        }
        else {
            Write-Warning2 "⚠ Got status $($_.Exception.Response.StatusCode)"
        }
    }
    
    # Test 4: Validation - invalid UUID
    Write-Info ""
    Write-Info "Test 4: Validation - Invalid UUID"
    $body = @{
        username = "test_user"
        userid   = "not-a-uuid"
        price    = 99.99
    } | ConvertTo-Json
    
    try {
        $response = Invoke-WebRequest -Uri "$url/api/purchases" -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Error2 "✗ Should have failed validation"
    }
    catch {
        if ($_.Exception.Response.StatusCode -eq 400) {
            Write-Success "✓ Validation correctly rejected invalid UUID"
        }
    }
    
    # Test 5: Get purchases
    Write-Info ""
    Write-Info "Test 5: Retrieve Purchases"
    try {
        $response = Invoke-WebRequest -Uri "$url/api/purchases" -Method Get -ErrorAction Stop
        $data = $response.Content | ConvertFrom-Json
        $count = ($data.purchases | Measure-Object).Count
        Write-Success "✓ Retrieved $count purchase(s)"
    }
    catch {
        Write-Error2 "✗ Get purchases error: $_"
    }
    
    Write-Info ""
    Write-Success "Testing complete! Check logs for structured JSON output:"
    Write-Info "  kubectl logs -n $Namespace -l app=unityexpress-api -f"
}

function Invoke-Logs {
    Write-Info "Fetching logs from API pods..."
    Write-Info "(Press Ctrl+C to stop)"
    Write-Info ""
    
    kubectl logs -n $Namespace -l app=unityexpress-api --tail=50 -f
}

function Invoke-Reset {
    Write-Warning2 "================================"
    Write-Warning2 "RESETTING DEPLOYMENT"
    Write-Warning2 "================================"
    Write-Warning2 "This will delete the entire namespace!"
    
    $confirm = Read-Host "Type 'yes' to confirm deletion"
    if ($confirm -ne 'yes') {
        Write-Info "Cancelled"
        return
    }
    
    Write-Info "Deleting namespace..."
    kubectl delete namespace $Namespace --wait=true
    Write-Success "✓ Namespace deleted"
}

# Main execution
try {
    Write-Info "UnityExpress Deployment Script"
    Write-Info "==============================="
    Write-Info ""
    
    Test-Prerequisites
    Test-DockerRunning
    
    Write-Info ""
    
    switch ($Action) {
        'build' { Invoke-Build }
        'deploy' { Invoke-Deploy }
        'test' { Invoke-Test }
        'logs' { Invoke-Logs }
        'reset' { Invoke-Reset }
        'all' {
            Invoke-Build
            Write-Info ""
            Invoke-Deploy
            Write-Info ""
            Invoke-Test
            Write-Info ""
            Write-Info "================================"
            Write-Success "✓ DEPLOYMENT COMPLETE"
            Write-Info "================================"
            Write-Info ""
            Write-Info "View real-time logs:"
            Write-Info "  .\deploy.ps1 -Action logs"
            Write-Info ""
        }
    }
    
    Write-Info ""
    Write-Success "✓ Script completed successfully"
}
catch {
    Write-Error2 "✗ Script failed: $_"
    exit 1
}
