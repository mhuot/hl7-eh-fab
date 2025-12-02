#!/bin/bash
# Deploy HL7 Listener to AKS
# Prerequisites: Infrastructure deployed via main.bicep

set -e

RESOURCE_GROUP=${1:-"hl7-demo-rg"}
IMAGE_TAG=${2:-"v1"}
LOCATION=${3:-"centralus"}
DEPLOYMENT_NAME="hl7Deployment-${LOCATION}"

echo "=== HL7 Listener Deployment ==="
echo "Resource Group: $RESOURCE_GROUP"
echo "Location: $LOCATION"
echo "Deployment: $DEPLOYMENT_NAME"

# Get deployment outputs
echo "Getting deployment outputs..."
ACR_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query "properties.outputs.acrName.value" -o tsv 2>/dev/null || \
           az acr list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)
ACR_LOGIN_SERVER=$(az acr show --name $ACR_NAME --query loginServer -o tsv)
AKS_NAME=$(az deployment sub show --name $DEPLOYMENT_NAME --query "properties.outputs.aksClusterName.value" -o tsv 2>/dev/null || \
           az aks list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)
EH_NAMESPACE=$(az deployment sub show --name $DEPLOYMENT_NAME --query "properties.outputs.eventHubNamespace.value" -o tsv 2>/dev/null || \
           az eventhubs namespace list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)

echo "ACR: $ACR_NAME ($ACR_LOGIN_SERVER)"
echo "AKS: $AKS_NAME"
echo "Event Hubs: $EH_NAMESPACE"

# Get AKS credentials
echo ""
echo "Getting AKS credentials..."
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_NAME --overwrite-existing

# Get Event Hubs connection string
echo "Getting Event Hubs connection string..."
EH_CONNECTION_STRING=$(az eventhubs namespace authorization-rule keys list \
  --resource-group $RESOURCE_GROUP \
  --namespace-name $EH_NAMESPACE \
  --name KafkaSendListen \
  --query primaryConnectionString -o tsv)

# Build and push image to ACR (ARM64 for AKS nodes)
echo ""
echo "Building and pushing image to ACR..."
az acr build --registry $ACR_NAME --image hl7listener:${IMAGE_TAG} --platform linux/arm64 ./src/hl7-listener/

# Deploy to Kubernetes
echo ""
echo "Deploying to Kubernetes..."

# Create namespace
kubectl apply -f k8s/namespace.yaml

# Create secret with actual values
kubectl create secret generic eventhub-credentials \
  --namespace hl7 \
  --from-literal=EVENTHUB_NAMESPACE=$EH_NAMESPACE \
  --from-literal=EVENTHUB_CONNECTION_STRING="$EH_CONNECTION_STRING" \
  --dry-run=client -o yaml | kubectl apply -f -

# Update deployment with ACR image and apply
sed "s|hl7listener:latest|${ACR_LOGIN_SERVER}/hl7listener:${IMAGE_TAG}|g" k8s/deployment.yaml > /tmp/deployment-updated.yaml
kubectl apply -f /tmp/deployment-updated.yaml

# Deploy service
kubectl apply -f k8s/service.yaml

# Wait for deployment
echo ""
echo "Waiting for deployment (timeout: 5 minutes)..."
if ! kubectl rollout status deployment/hl7-listener -n hl7 --timeout=300s; then
  echo ""
  echo "⚠️  Deployment is taking longer than expected. Checking status..."
  echo ""
  echo "=== Pod Status ==="
  kubectl get pods -n hl7 -o wide
  echo ""
  echo "=== Pod Events ==="
  kubectl describe pods -n hl7 -l app=hl7-listener | grep -A 20 "Events:"
  echo ""
  echo "=== Recent Pod Logs (if available) ==="

  echo ""
  echo "The deployment is still in progress. You can:"
  echo "  1. Wait and check status:  kubectl get pods -n hl7 -w"
  echo "  2. View logs:              kubectl logs -n hl7 -l app=hl7-listener -f"
  echo "  3. Describe pods:          kubectl describe pods -n hl7"
  echo ""
  echo "Common issues:"
  echo "  - Image pull errors: Check ACR permissions"
  echo "  - CrashLoopBackOff: Check Event Hubs connection string"
  echo "  - Pending: Check node resources (kubectl describe nodes)"
  exit 1
fi

# Cleanup temp file
rm -f /tmp/deployment-updated.yaml

# Get external IP
echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Getting external IP (Ctrl+C when IP appears)..."
kubectl get service hl7-listener -n hl7 -w
