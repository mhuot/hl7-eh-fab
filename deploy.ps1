# Deploy HL7 Listener to AKS
# Prerequisites: Infrastructure deployed via infra/main.bicep
# Usage: .\deploy.ps1 [-ResourceGroup "hl7-demo-rg"] [-ImageTag "v1"]

param(
    [string]$ResourceGroup = "hl7-demo-rg",
    [string]$ImageTag = "v1"
)

$ErrorActionPreference = "Stop"

Write-Host "=== HL7 Listener Deployment ===" -ForegroundColor Cyan
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Image Tag: $ImageTag"

# Pre-flight checks
Write-Host "`nChecking prerequisites..." -ForegroundColor Yellow

# Check Azure CLI
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI not found. Install from https://aka.ms/installazurecli" -ForegroundColor Red
    exit 1
}

# Check kubectl
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: kubectl not found. Install via: az aks install-cli" -ForegroundColor Red
    exit 1
}

# Check Azure login
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "ERROR: Not logged in to Azure. Run: az login" -ForegroundColor Red
    exit 1
}
Write-Host "Logged in as: $($account.user.name)" -ForegroundColor Green

# Get deployment outputs
Write-Host "`nGetting deployment outputs..." -ForegroundColor Yellow

$ACR_NAME = az acr list --resource-group $ResourceGroup --query "[0].name" -o tsv
if (-not $ACR_NAME) {
    Write-Host "ERROR: No ACR found in resource group $ResourceGroup. Deploy infrastructure first." -ForegroundColor Red
    exit 1
}

$ACR_LOGIN_SERVER = az acr show --name $ACR_NAME --query loginServer -o tsv
$AKS_NAME = az aks list --resource-group $ResourceGroup --query "[0].name" -o tsv
$EH_NAMESPACE = az eventhubs namespace list --resource-group $ResourceGroup --query "[0].name" -o tsv

Write-Host "ACR: $ACR_NAME ($ACR_LOGIN_SERVER)"
Write-Host "AKS: $AKS_NAME"
Write-Host "Event Hubs: $EH_NAMESPACE"

# Get AKS credentials
Write-Host "`nGetting AKS credentials..." -ForegroundColor Yellow
az aks get-credentials --resource-group $ResourceGroup --name $AKS_NAME --overwrite-existing

# Get Event Hubs connection string
Write-Host "Getting Event Hubs connection string..." -ForegroundColor Yellow
$EH_CONNECTION_STRING = az eventhubs namespace authorization-rule keys list `
    --resource-group $ResourceGroup `
    --namespace-name $EH_NAMESPACE `
    --name KafkaSendListen `
    --query primaryConnectionString -o tsv

# Build and push image to ACR
Write-Host "`nBuilding and pushing image to ACR..." -ForegroundColor Yellow
az acr build --registry $ACR_NAME --image "hl7listener:$ImageTag" ./src/hl7-listener/

# Deploy to Kubernetes
Write-Host "`nDeploying to Kubernetes..." -ForegroundColor Yellow

# Create namespace
kubectl apply -f k8s/namespace.yaml

# Create secret with actual values
$secretYaml = kubectl create secret generic eventhub-credentials `
    --namespace hl7 `
    --from-literal="EVENTHUB_NAMESPACE=$EH_NAMESPACE" `
    --from-literal="EVENTHUB_CONNECTION_STRING=$EH_CONNECTION_STRING" `
    --dry-run=client -o yaml

$secretYaml | kubectl apply -f -

# Update deployment with ACR image and apply
$deploymentContent = Get-Content k8s/deployment.yaml -Raw
$updatedDeployment = $deploymentContent -replace "hl7listener:latest", "$ACR_LOGIN_SERVER/hl7listener:$ImageTag"
$tempFile = [System.IO.Path]::GetTempFileName()
$updatedDeployment | Set-Content $tempFile
kubectl apply -f $tempFile
Remove-Item $tempFile

# Deploy service
kubectl apply -f k8s/service.yaml

# Wait for deployment
Write-Host "`nWaiting for deployment..." -ForegroundColor Yellow
kubectl rollout status deployment/hl7-listener -n hl7 --timeout=240s

# Get external IP
Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
Write-Host "`nService details:" -ForegroundColor Yellow
kubectl get service hl7-listener -n hl7

Write-Host "`nWaiting for external IP (Ctrl+C to exit)..." -ForegroundColor Yellow
kubectl get service hl7-listener -n hl7 -w
